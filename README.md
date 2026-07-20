# finally-good-blocker-mac

A deliberately small personal macOS application blocker. It observes application
activation, hides configured targets, and presents the same invisible-progress
`press and hold` interaction as the sibling Firefox extension.

The initial rule blocks Messages (`com.apple.MobileSMS`) with the extension's
default timing: hold for 10 seconds to earn 30 seconds, plus 5 seconds of access
for each additional second held.

## Build and test

The project uses Swift Package Manager because this Mac currently has the command
line developer tools rather than the full Xcode application.

```sh
swift run AccessCalculationChecks
zsh scripts/package-app.sh
open build/finally-good-blocker.app
```

The packaging script creates and ad-hoc signs a normal `.app` bundle. Quit it with
Command-Q or from its Dock menu.

When a target is blocked, its window is hidden and a normal blocker window opens.
You may close that window or switch away from it; neither action grants access.
Activating the target again reopens the blocker.

The blocker listens for target launch, unhide, and activation events. When window
bounds are available, it covers the target's visible window directly to reduce
content flashing while the asynchronous hide request completes.

The menu bar shows an hourglass while the blocker is idle. During an access grant,
it changes to the remaining time as `m:ss`; the Dock icon shows the same countdown.
Quitting Messages immediately clears the grant and countdown, so its next launch
is blocked again.

This reset is tied to actual process termination. Use Messages → Quit Messages or
Command-Q; closing the red window leaves Messages running and does not reset time.

When a grant expires, every running Messages instance is hidden immediately. The
app is not force-quit, so drafts and open conversations remain intact.

## Change blocked applications

Edit `rules` in `Sources/FinallyGoodBlockerMac/AppController.swift`. Rules match
exact bundle identifiers and all use the same enforcement path.

## Limits

This is cooperative friction, not security software. Some applications may reject
or undo `NSRunningApplication.hide()`. The blocker still takes focus after making
the hide request; it does not request Accessibility access or install a helper.

Grants exist only in memory. Quitting or relaunching the blocker resets them.
