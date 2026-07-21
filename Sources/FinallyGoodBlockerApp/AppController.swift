import AppKit
import BlockerCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let workspace = NSWorkspace.shared
    private let blockerPanel = BlockerPanel()
    private var statusItem: NSStatusItem?

    private let rulesByBundleIdentifier: [String: Rule] = {
        let rules = [
            Rule(
                bundleIdentifier: "com.apple.MobileSMS",
                scheme: .default
            ),
        ]
        return Dictionary(uniqueKeysWithValues: rules.map {
            ($0.bundleIdentifier, $0)
        })
    }()

    private var accessUntilByBundleIdentifier: [String: Date] = [:]
    private var grantProcessIdentifiersByBundleIdentifier: [String: Set<pid_t>] = [:]
    private var pendingTarget: NSRunningApplication?
    private var pendingTargetExitTimer: Timer?
    private var grantTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        blockerPanel.onHoldFinished = { [weak self] heldSeconds in
            self?.finishHold(heldSeconds: heldSeconds)
        }

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.willLaunchApplicationNotification,
            object: nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        NSLog("finally-good-blocker-app is running with %d rule(s)", rulesByBundleIdentifier.count)

        // Leave the previous application in front until something is blocked.
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }
        perform(
            #selector(evaluateFrontmostApplication),
            with: nil,
            afterDelay: 0.2
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPendingTargetExitPolling()
        stopGrantCountdown()
        workspace.notificationCenter.removeObserver(self)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else {
            return
        }

        handleActivation(of: application)
    }

    @objc private func evaluateFrontmostApplication() {
        guard let application = workspace.frontmostApplication else {
            return
        }

        handleActivation(of: application)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else {
            return
        }

        let configuredBundleIdentifier = application.bundleIdentifier.flatMap {
            rulesByBundleIdentifier[$0] == nil ? nil : $0
        }
        let grantedBundleIdentifier = grantProcessIdentifiersByBundleIdentifier
            .first(where: { $0.value.contains(application.processIdentifier) })?
            .key
        let terminatedBundleIdentifier = configuredBundleIdentifier
            ?? grantedBundleIdentifier

        if let bundleIdentifier = terminatedBundleIdentifier {
            resetGrant(for: bundleIdentifier)
        }

        let matchesPendingProcess = application.processIdentifier
            == pendingTarget?.processIdentifier
        let matchesPendingBundle = terminatedBundleIdentifier != nil
            && terminatedBundleIdentifier == pendingTarget?.bundleIdentifier

        if matchesPendingProcess || matchesPendingBundle {
            dismissPendingBlocker()
            NSLog(
                "finally-good-blocker-app: dismissed blocker after %@ terminated",
                terminatedBundleIdentifier ?? "unknown application"
            )
        }
    }

    private func handleActivation(of application: NSRunningApplication) {
        guard
            let bundleIdentifier = application.bundleIdentifier,
            let rule = rulesByBundleIdentifier[bundleIdentifier]
        else {
            return
        }

        if let accessUntil = accessUntilByBundleIdentifier[bundleIdentifier],
           Date.now < accessUntil {
            grantProcessIdentifiersByBundleIdentifier[bundleIdentifier, default: []]
                .insert(application.processIdentifier)
            pendingTarget = nil
            stopPendingTargetExitPolling()
            blockerPanel.dismiss()
            startGrantCountdown(for: rule, until: accessUntil)
            return
        }

        resetGrant(for: bundleIdentifier)

        let targetWindowFrame = visibleWindowFrame(for: application)
        pendingTarget = application
        startPendingTargetExitPolling(for: bundleIdentifier)
        blockerPanel.present(over: targetWindowFrame)
        let hideRequestReportedSuccess = application.hide()
        let targetProcessIdentifier = application.processIdentifier
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.pendingTarget?.processIdentifier == targetProcessIdentifier
            else {
                return
            }

            self.blockerPanel.reassertFocus()
        }
        if !hideRequestReportedSuccess {
            NSLog(
                "finally-good-blocker-app: hide() returned false for %@; presenting the blocker anyway",
                bundleIdentifier
            )
        }
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(retryPendingTargetHide),
            object: nil
        )
        perform(
            #selector(retryPendingTargetHide),
            with: nil,
            afterDelay: 0.2
        )
    }

    @objc private func retryPendingTargetHide() {
        guard
            let target = pendingTarget,
            let bundleIdentifier = target.bundleIdentifier,
            rulesByBundleIdentifier[bundleIdentifier] != nil,
            accessUntilByBundleIdentifier[bundleIdentifier] == nil
        else {
            return
        }

        _ = target.hide()
        blockerPanel.reassertFocus()
    }

    private func finishHold(heldSeconds: TimeInterval) {
        guard
            let target = pendingTarget,
            let bundleIdentifier = target.bundleIdentifier,
            let rule = rulesByBundleIdentifier[bundleIdentifier]
        else {
            return
        }

        let earnedSeconds = calculateEarnedSeconds(
            heldSeconds: heldSeconds,
            scheme: rule.scheme
        )
        guard earnedSeconds > 0 else {
            return
        }

        let accessUntil = Date.now.addingTimeInterval(TimeInterval(earnedSeconds))
        accessUntilByBundleIdentifier[bundleIdentifier] = accessUntil
        grantProcessIdentifiersByBundleIdentifier[bundleIdentifier] = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .map(\.processIdentifier)
        )
        pendingTarget = nil
        stopPendingTargetExitPolling()
        blockerPanel.dismiss()

        _ = target.unhide()
        _ = target.activate(options: [.activateAllWindows])
        startGrantCountdown(for: rule, until: accessUntil)
    }

    private func startPendingTargetExitPolling(for bundleIdentifier: String) {
        stopPendingTargetExitPolling()

        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(pendingTargetExitTimerFired(_:)),
            userInfo: bundleIdentifier,
            repeats: true
        )
        pendingTargetExitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func pendingTargetExitTimerFired(_ timer: Timer) {
        guard
            let bundleIdentifier = timer.userInfo as? String,
            pendingTarget?.bundleIdentifier == bundleIdentifier
        else {
            stopPendingTargetExitPolling()
            return
        }

        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty else {
            return
        }

        resetGrant(for: bundleIdentifier)
        dismissPendingBlocker()
    }

    private func stopPendingTargetExitPolling() {
        pendingTargetExitTimer?.invalidate()
        pendingTargetExitTimer = nil
    }

    private func dismissPendingBlocker() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(retryPendingTargetHide),
            object: nil
        )
        pendingTarget = nil
        stopPendingTargetExitPolling()
        blockerPanel.dismiss()
        NSApp.hide(nil)
    }

    private func startGrantCountdown(for rule: Rule, until deadline: Date) {
        grantTimer?.invalidate()
        updateCountdown(until: deadline)

        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(grantTimerFired(_:)),
            userInfo: rule.bundleIdentifier,
            repeats: true
        )
        grantTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func grantTimerFired(_ timer: Timer) {
        guard
            let bundleIdentifier = timer.userInfo as? String,
            let deadline = accessUntilByBundleIdentifier[bundleIdentifier]
        else {
            stopGrantCountdown()
            return
        }

        guard Date.now >= deadline else {
            updateCountdown(until: deadline)
            return
        }

        resetGrant(for: bundleIdentifier)

        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        guard !runningApplications.isEmpty else {
            return
        }

        let foregroundApplication = runningApplications.first(where: \.isActive)
        for application in runningApplications where application != foregroundApplication {
            _ = application.hide()
        }

        if let foregroundApplication {
            handleActivation(of: foregroundApplication)
        }
    }

    private func visibleWindowFrame(for application: NSRunningApplication) -> NSRect? {
        guard
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]],
            let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY
        else {
            return nil
        }

        return windowInfo.compactMap { window -> NSRect? in
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.int32Value == application.processIdentifier,
                let layer = window[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let cgRect = CGRect(dictionaryRepresentation: bounds),
                cgRect.width >= 300,
                cgRect.height >= 200
            else {
                return nil
            }

            return NSRect(
                x: cgRect.minX,
                y: primaryScreenMaxY - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
        }
        .max(by: { $0.width * $0.height < $1.width * $1.height })
    }

    private func updateCountdown(until deadline: Date) {
        let remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let countdown = String(format: "%d:%02d", minutes, seconds)

        statusItem?.button?.image = nil
        statusItem?.button?.title = countdown
        statusItem?.button?.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        statusItem?.button?.toolTip = "Messages time remaining: \(countdown)"
    }

    private func stopGrantCountdown() {
        grantTimer?.invalidate()
        grantTimer = nil
        showIdleStatusItem()
    }

    private func resetGrant(for bundleIdentifier: String) {
        accessUntilByBundleIdentifier[bundleIdentifier] = nil
        grantProcessIdentifiersByBundleIdentifier[bundleIdentifier] = nil
        if grantTimer?.userInfo as? String == bundleIdentifier {
            stopGrantCountdown()
        }
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        let menu = NSMenu()
        let protectedItem = NSMenuItem(
            title: "Blocker stays running",
            action: nil,
            keyEquivalent: ""
        )
        protectedItem.isEnabled = false
        menu.addItem(protectedItem)
        statusItem.menu = menu
        self.statusItem = statusItem
        showIdleStatusItem()
    }

    private func showIdleStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        let image = NSImage(
            systemSymbolName: "hourglass",
            accessibilityDescription: "finally-good-blocker-app"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "finally-good-blocker-app is running"
    }

}

@main
@MainActor
private enum FinallyGoodBlockerAppMain {
    private static var controller: AppController?

    static func main() {
        let application = NSApplication.shared
        let controller = AppController()
        self.controller = controller
        application.delegate = controller
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
