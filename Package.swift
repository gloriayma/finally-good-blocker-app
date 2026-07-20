// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "finally-good-blocker-app",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "FinallyGoodBlockerMac",
            targets: ["FinallyGoodBlockerMac"]
        ),
    ],
    targets: [
        .target(
            name: "BlockerCore",
            path: "Sources/BlockerCore"
        ),
        .executableTarget(
            name: "FinallyGoodBlockerMac",
            dependencies: ["BlockerCore"],
            path: "Sources/FinallyGoodBlockerMac"
        ),
        .executableTarget(
            name: "AccessCalculationChecks",
            dependencies: ["BlockerCore"],
            path: "Tests/AccessCalculationChecks"
        ),
    ]
)
