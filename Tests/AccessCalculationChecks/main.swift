import BlockerCore
import Darwin
import Foundation

private var failureCount = 0

@MainActor
private func check(
    _ description: String,
    _ actual: @autoclosure () -> Int,
    equals expected: Int
) {
    let actual = actual()
    if actual == expected {
        print("✓ \(description)")
    } else {
        failureCount += 1
        print("✗ \(description): expected \(expected), got \(actual)")
    }
}

let scheme = AccessScheme.default

check(
    "below threshold earns nothing",
    calculateEarnedSeconds(heldSeconds: 9.999, scheme: scheme),
    equals: 0
)
check(
    "exact threshold earns base access",
    calculateEarnedSeconds(heldSeconds: 10, scheme: scheme),
    equals: 30
)
check(
    "extra hold time earns the configured rate",
    calculateEarnedSeconds(heldSeconds: 12, scheme: scheme),
    equals: 40
)
check(
    "fractional earned time is floored",
    calculateEarnedSeconds(heldSeconds: 10.19, scheme: scheme),
    equals: 30
)
check(
    "zero extra rate always returns base access",
    calculateEarnedSeconds(
        heldSeconds: 100,
        scheme: AccessScheme(
            holdThresholdSeconds: 10,
            baseAccessSeconds: 30,
            accessSecondsPerExtraHoldSecond: 0
        )
    ),
    equals: 30
)

if failureCount > 0 {
    exit(EXIT_FAILURE)
}
