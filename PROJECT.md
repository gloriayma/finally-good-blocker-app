# finally-good-blocker-app

Last updated: 2026-07-20

Status: v0 is implemented and packaged. Automated access-calculation checks pass;
normal daily-use validation and a second personal target remain.

## Purpose

This is a small personal macOS friction tool. When a configured application is
activated, the blocker attempts to hide it and shows a window containing one
unchanging `press and hold` control. A sufficiently long hold grants temporary
access to that application.

This is not parental control, security software, or tamper-resistant enforcement.
Deliberately unloading or deleting its per-user LaunchAgent remains an accepted
bypass.

## Smallest useful version

The first version does only the following:

1. Start as a menu-bar application managed by one per-user LaunchAgent.
2. Keep a short, hard-coded list of blocked bundle identifiers and timing values.
3. Observe foreground application activation with `NSWorkspace`.
4. When a configured application activates without an active grant, attempt to
   hide it and show one blocker window.
5. Measure a pointer hold using a monotonic clock.
6. On a qualifying release, create an in-memory wall-clock deadline, dismiss the
   blocker, and reactivate the target.
7. If that deadline expires while the target is foreground, attempt to hide it
   again and show the blocker.

Messages (`com.apple.MobileSMS`) is the first test target. Other targets use the
same exact-bundle-identifier path; adding a target must not require target-specific
enforcement code.

## Explicitly deferred

Do not build any of these until using the small version demonstrates a real need:

- application picker or settings window;
- editable or per-application UI configuration;
- persisted grants or restoration after blocker relaunch;
- versioned schemas, migrations, corrupt-data backups, or a state store;
- app icons, display-name caching, saved paths, UUID rule identities, or a system
  application denylist;
- keyboard hold input, VoiceOver-specific behavior, or elaborate pointer-state
  handling unless personally needed;
- full-screen, every-Space, or multiple-display guarantees;
- sandbox compatibility work;
- Accessibility permission, helper processes, overlays, polling, or privileged
  enforcement;
- escalation, recovery levels, arbitrary access curves, combined reports, or
  cross-process activity import;
- distribution, notarization, checksums, screenshots, or release packaging.

Deferred work is not predesigned. Add the smallest change that resolves an
observed problem when it appears.

## Configuration

Configuration initially lives in source code:

```swift
struct Rule {
    let bundleIdentifier: String
    let holdThresholdSeconds: Double
    let baseAccessSeconds: Double
    let accessSecondsPerExtraHoldSecond: Double
}

let rules = [
    Rule(
        bundleIdentifier: "com.apple.MobileSMS",
        holdThresholdSeconds: 10,
        baseAccessSeconds: 30,
        accessSecondsPerExtraHoldSecond: 5
    )
]
```

Recompiling to change this list is acceptable for v0. A picker becomes justified
only if this is genuinely inconvenient in use.

## Access calculation

```text
if heldSeconds < holdThresholdSeconds:
    earnedSeconds = 0
else:
    earnedSeconds = floor(
        baseAccessSeconds
        + (heldSeconds - holdThresholdSeconds)
          * accessSecondsPerExtraHoldSecond
    )
```

An early or cancelled release grants nothing. Hold duration uses
`ContinuousClock`. Access uses an absolute `Date` deadline so backgrounding or
sleep does not intentionally pause it.

## Runtime state

Keep only in-memory state, on the main actor:

```text
accessUntilByBundleIdentifier: [String: Date]
pendingTarget: NSRunningApplication?
holdStartedAt: ContinuousClock.Instant?
foregroundExpiryTimer: Timer?
```

There is no persisted runtime state. Relaunching the blocker starts with every
configured application blocked.

## Enforcement flow

### Blocked activation

1. Receive an application-activation notification.
2. Match the exact bundle identifier against `rules`.
3. Allow the application if `Date.now < accessUntil`.
4. Listen to launch, unhide, and activation events so interception begins at the
   earliest ordinary workspace event available.
5. Capture the target's visible window bounds when available, then call `hide()`.
6. Cover those bounds with the blocker while the asynchronous hide completes.
7. Remember the target and bring the blocker window forward immediately after
   the hide request. Retry the hide once after the focus transition settles.
8. Present the blocker even if `hide()` returns `false`. On the owner's current
   macOS version, Messages may still hide on the next run-loop turn despite that
   return value.
9. Present the blocker as a normal closable window without requiring background
   focus stealing. It appears above the application macOS selects after hiding
   the target, but does not remain always-on-top after the user switches away.
   Closing it grants nothing; activating the target again presents it again.

`NSRunningApplication.hide()` is cooperative and race-prone. A target may unhide
itself. The first version provides useful friction for applications on which the
simple mechanism works; it does not guarantee control of every macOS application.

### Hold release

1. Measure elapsed hold time with `ContinuousClock`.
2. Calculate earned access using the matching hard-coded rule.
3. If the result is zero, clear the hold and do nothing.
4. Otherwise set the in-memory deadline before requesting target activation.
5. Dismiss the blocker and reactivate the remembered target.
6. Schedule one timer for that foreground target's deadline.
7. Show the remaining grant as `m:ss` in the menu bar.

There is no durable-write requirement. `UserDefaults` is not part of this flow.

### Expiry

When the foreground timer fires:

1. Compare the current wall clock with the deadline; the timer itself is not
   authoritative.
2. Inspect the actual frontmost application.
3. If the deadline is expired and that application has the matching bundle
   identifier, attempt to hide it and show the blocker.
4. Otherwise do nothing. A background target is checked the next time it
   activates.

If the target application terminates, immediately remove its grant and stop the
timer. Its next launch starts blocked.

If ordinary testing shows that the timer does not reevaluate promptly after wake,
add one `NSWorkspace.didWakeNotification` observer. Do not add lifecycle machinery
before that failure is observed.

## Code shape

The implementation uses one application target and three production source files:

```text
Sources/
├── BlockerCore/
│   └── AccessCalculation.swift   # rules and pure earned-access function
└── FinallyGoodBlockerMac/
    ├── AppController.swift       # app lifecycle, observation, grants, timer
    └── BlockerPanel.swift        # one window and its hold control
```

Use AppKit directly. Keep persistence to one LaunchAgent plist and two shell
scripts. Do not introduce a helper process, settings system, coordinator protocol,
dependency-injection, or event-bus layer.

## Feasibility spike

Before polishing anything:

1. Create a locally signed, unsandboxed macOS app.
2. Log bundle identifiers from `NSWorkspace` activation notifications.
3. Hard-code Messages and test `hide()` plus reactivation.
4. Add the blocker window and hold calculation.
5. Verify expiry while Messages is foreground.
6. Add one other personally relevant application and verify the same path.
7. Use the result normally for a day.

If an application cannot be hidden reliably, mark it unsupported. Investigate a
stronger mechanism only if that specific application is important enough to
justify the additional complexity.

## Verification

Automated tests are limited to the pure calculation:

1. below threshold earns zero;
2. exact threshold earns base access;
3. extra hold time earns the configured rate;
4. fractional earned seconds are floored;
5. zero extra rate works.

Manual v0 checks:

1. activating Messages from the Dock presents the blocker;
2. Command-Tab activation presents the blocker;
3. early release grants nothing;
4. a qualifying release activates Messages;
5. foreground expiry hides Messages again;
6. the same behavior works for one other relevant application;
7. killing the blocker process causes launchd to relaunch it;
8. the uninstall script cleanly removes the app and LaunchAgent.

Add tests for lifecycle or input cases only after a real failure or regression.

## v0 acceptance criteria

The first usable version is complete when:

1. one application process observes activations without polling;
2. Messages and one other personally relevant app use the same rule path;
3. an unconfigured app is unaffected;
4. a blocked activation that can be hidden presents one blocker window;
5. the window contains only the unchanged hold control;
6. early release grants nothing;
7. successful release grants the calculated wall-clock access;
8. expiry re-hides a foreground target without quitting it;
9. a misleading `hide()` return value does not suppress the blocker window;
10. the app has no ordinary Quit command and is relaunched if its process exits.

## Decisions to revisit only after use

1. Add a picker only if recompiling configuration becomes annoying.
2. Persist grants only if losing grant state on relaunch causes a real problem.
3. Add keyboard hold support only if it will actually be used.
4. Test or support full-screen, other Spaces, and multiple displays according to
   the owner's real workflow, not as an abstract compatibility promise.

## Firefox integration — planned, not built

The intended integration is possible, but it cannot be implemented by pointing
the Firefox extension at the macOS app's files. WebExtensions run inside Firefox
and their `browser.storage.local` data is not directly readable by an ordinary
macOS application. The supported bridge is Firefox native messaging.

This integration must remain out of the enforcement feasibility spike. The
browser tracker is already useful independently, and the macOS blocker must
first prove that generic application blocking works. After both sides have
durable activity sessions, add the bridge as a separate phase.

### Shared activity concept

Browser and application activity use one conceptual session model:

```text
ActivitySession
  id: stable unique string
  source: firefox | macos
  kind: website | application
  identifier: configured hostname | exact bundle identifier
  startedAt: wall-clock timestamp
  endedAt: wall-clock timestamp
  durationMilliseconds: nonnegative integer
```

Source-specific metadata such as a Firefox tab ID or macOS process identifier is
diagnostic only. It must not participate in identity because those values can be
reused after a browser or application restart.

The Firefox extension now stores one completed record per visit with a stable
ID, `source: firefox`, `kind: website`, the configured hostname, timestamps, and
duration. It deliberately does not store page paths, query strings, titles,
content, clicks, or keystrokes. A future macOS logger should emit the analogous
record with `source: macos`, `kind: application`, and an exact bundle identifier.

### Bridge shape

1. The macOS installation adds a small native-messaging executable and a host
   manifest named `ma.gloria.finally_good_blocker.json` under the current user's
   `~/Library/Application Support/Mozilla/NativeMessagingHosts/` directory.
2. The manifest uses `type: stdio`, an absolute executable path, and
   `allowed_extensions: ["finally-good-blocker@gloria.ma"]`.
3. Only after that host exists, the Firefox extension adds the
   `nativeMessaging` permission and connects to
   `ma.gloria.finally_good_blocker` from its background script.
4. The extension sends completed sessions as JSON. The host validates the
   version, source, kind, hostname, timestamps, duration, and reasonable message
   size before writing anything.
5. The host writes to the macOS app's local SQLite activity database and replies
   with the stable session ID only after the transaction commits.
6. The extension marks that ID delivered only after the acknowledgement. A
   disconnect, app absence, or malformed reply leaves it pending for retry.
7. The SQLite session ID is a primary key. Delivery is therefore at-least-once,
   while storage is effectively once: retries replace nothing and create no
   duplicates.
8. The first successful connection backfills all previously undelivered Firefox
   visit records, including records created before the macOS app was installed.

Use a short-lived `runtime.sendNativeMessage()` process for an initial prototype
unless measurements show that process startup is excessive. A long-lived port,
XPC service, shared app group, cloud service, socket server, or custom URL scheme
is unnecessary for this one-way local import.

### Ownership and privacy boundaries

- Firefox remains the source of truth for browser sessions until each session is
  acknowledged by the native host.
- The macOS SQLite database becomes the combined history and deduplicates all
  imported records by ID.
- Blocking rules and access grants remain owned by their original product. The
  bridge shares activity history, not enforcement state or unlock timers.
- Nothing crosses the network. The native host must not log raw JSON messages to
  a system log because they contain browsing hostnames.
- Deleting a browser blocking rule continues browser tracking by explicit user
  request. A later history UI needs a separate `stop tracking` action; it must
  not overload `remove block` with two meanings.
- Uninstall and deletion semantics need an explicit UI decision before a combined
  history screen ships. Do not silently erase either source's historical data.

### Integration verification gate

The bridge is complete only when tests demonstrate:

1. a Firefox visit imports with the same ID, hostname, timestamps, and duration;
2. a repeated delivery does not create a second row;
3. a native-host crash before acknowledgement causes a safe retry;
4. a native-host crash after commit but before acknowledgement still deduplicates;
5. visits accumulated while the app is absent backfill after installation;
6. invalid, oversized, or unsupported-version messages are rejected without a
   partial database write;
7. Messages and a third-party application produce generic application sessions;
8. combined queries can order website and application sessions on one timeline;
9. no blocking rule, grant, or browser history changes during import; and
10. all behavior works with networking disabled.

### Integration sequence

1. Finish the generic macOS enforcement feasibility spike.
2. Add local macOS application-session recording independently of Firefox.
3. Add the SQLite activity schema and migration test.
4. Add the native-messaging executable and per-user host-manifest installer.
5. Add the extension permission, durable delivery markers, retry, and backfill.
6. Add a minimal combined-history reader only after the stored data has proved
   useful; do not build charts or analytics preemptively.

## Living work record

- 2026-07-20: Created the generic macOS blocker plan. No application code exists.
- 2026-07-20: Added the planned local Firefox native-messaging integration,
  shared activity-session contract, delivery semantics, privacy boundaries,
  sequencing, and verification gate. The bridge and macOS activity recorder are
  not built. The sibling Firefox extension's standalone visit recorder is built
  and is the future source of browser sessions.
- 2026-07-20: Added the observed persistence requirement as a menu-bar app plus
  one per-user LaunchAgent with `RunAtLoad` and `KeepAlive`; no helper process.

## Immediate next action

Install the persistent build and use it normally. Add one other personally
relevant bundle identifier only if needed; do not add settings or future-policy
infrastructure without another concrete need.
