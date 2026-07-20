import Foundation

public struct AccessScheme: Equatable, Sendable {
    public static let `default` = AccessScheme(
        holdThresholdSeconds: 10,
        baseAccessSeconds: 30,
        accessSecondsPerExtraHoldSecond: 5
    )

    public let holdThresholdSeconds: Double
    public let baseAccessSeconds: Double
    public let accessSecondsPerExtraHoldSecond: Double

    public init(
        holdThresholdSeconds: Double,
        baseAccessSeconds: Double,
        accessSecondsPerExtraHoldSecond: Double
    ) {
        self.holdThresholdSeconds = holdThresholdSeconds
        self.baseAccessSeconds = baseAccessSeconds
        self.accessSecondsPerExtraHoldSecond = accessSecondsPerExtraHoldSecond
    }
}

public struct Rule: Equatable, Sendable {
    public let bundleIdentifier: String
    public let scheme: AccessScheme

    public init(bundleIdentifier: String, scheme: AccessScheme) {
        self.bundleIdentifier = bundleIdentifier
        self.scheme = scheme
    }
}

public func calculateEarnedSeconds(
    heldSeconds: TimeInterval,
    scheme: AccessScheme
) -> Int {
    let heldSeconds = max(0, heldSeconds)

    guard heldSeconds >= scheme.holdThresholdSeconds else {
        return 0
    }

    let extraHoldSeconds = heldSeconds - scheme.holdThresholdSeconds
    return Int(floor(
        scheme.baseAccessSeconds
            + extraHoldSeconds * scheme.accessSecondsPerExtraHoldSecond
    ))
}
