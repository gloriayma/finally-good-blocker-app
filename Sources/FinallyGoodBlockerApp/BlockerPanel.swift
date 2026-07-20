import AppKit

@MainActor
final class BlockerPanel: NSPanel {
    private static let defaultSize = NSSize(width: 700, height: 360)
    private let holdControl = HoldControl(frame: .zero)

    var onHoldFinished: ((TimeInterval) -> Void)? {
        get { holdControl.onHoldFinished }
        set { holdControl.onHoldFinished = newValue }
    }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isOpaque = true
        title = "finally-good-blocker-app"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .blockerPaper
        hasShadow = true
        hidesOnDeactivate = false
        level = .normal
        animationBehavior = .documentWindow
        collectionBehavior = [.moveToActiveSpace]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let paperView = NSView(frame: contentRect(forFrameRect: frame))
        paperView.wantsLayer = true
        paperView.layer?.backgroundColor = NSColor.blockerPaper.cgColor
        contentView = paperView

        holdControl.translatesAutoresizingMaskIntoConstraints = false
        paperView.addSubview(holdControl)

        NSLayoutConstraint.activate([
            holdControl.widthAnchor.constraint(equalToConstant: 430),
            holdControl.heightAnchor.constraint(equalToConstant: 84),
            holdControl.centerXAnchor.constraint(equalTo: paperView.centerXAnchor),
            holdControl.topAnchor.constraint(equalTo: paperView.topAnchor, constant: 72),
        ])
    }

    override var canBecomeKey: Bool { true }

    func present(over targetFrame: NSRect?) {
        if let targetFrame {
            let size = NSSize(
                width: max(targetFrame.width, Self.defaultSize.width),
                height: max(targetFrame.height, Self.defaultSize.height)
            )
            let coveringFrame = NSRect(
                x: targetFrame.midX - size.width / 2,
                y: targetFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            setFrame(coveringFrame, display: true)
        } else if !isVisible {
            setContentSize(Self.defaultSize)
            centerOnActiveScreen()
        }

        NSApp.unhide(nil)
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
    }

    private func centerOnActiveScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        setFrameOrigin(origin)
    }
}

@MainActor
private final class HoldControl: NSControl {
    var onHoldFinished: ((TimeInterval) -> Void)?

    private let clock = ContinuousClock()

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.blockerPaper.setFill()
        bounds.fill()

        let lineRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath(roundedRect: lineRect, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1
        NSColor.blockerInk.setStroke()
        outline.stroke()

        let text = NSAttributedString(
            string: "press and hold",
            attributes: [
                .font: NSFont.systemFont(ofSize: 17.6, weight: .regular),
                .foregroundColor: NSColor.blockerInk,
            ]
        )
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        ))
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, let window else {
            return
        }

        let startedAt = clock.now

        while true {
            guard let nextEvent = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else {
                return
            }

            if nextEvent.type == .leftMouseUp {
                let duration = startedAt.duration(to: clock.now)
                onHoldFinished?(duration.timeInterval)
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

private extension NSColor {
    static let blockerPaper = NSColor(
        calibratedRed: 255 / 255,
        green: 253 / 255,
        blue: 248 / 255,
        alpha: 1
    )

    static let blockerInk = NSColor(
        calibratedRed: 45 / 255,
        green: 41 / 255,
        blue: 38 / 255,
        alpha: 1
    )
}
