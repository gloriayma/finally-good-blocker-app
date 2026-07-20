// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "finally-good-blocker-app",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "FinallyGoodBlockerApp",
            targets: ["FinallyGoodBlockerApp"]
        ),
    ],
    targets: [
        .target(
            name: "BlockerCore",
            path: "Sources/BlockerCore"
        ),
        .executableTarget(
            name: "FinallyGoodBlockerApp",
            dependencies: ["BlockerCore"],
            path: "Sources/FinallyGoodBlockerApp"
        ),
        .executableTarget(
            name: "AccessCalculationChecks",
            dependencies: ["BlockerCore"],
            path: "Tests/AccessCalculationChecks"
        ),
    ]
)
