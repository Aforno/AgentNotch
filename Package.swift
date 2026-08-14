// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentsNotch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AgentsNotchCore", targets: ["AgentsNotchCore"]),
        .executable(name: "AgentsNotch", targets: ["AgentsNotch"]),
        .executable(name: "AgentsNotchHook", targets: ["AgentsNotchHook"]),
    ],
    targets: [
        .target(
            name: "AgentsNotchCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AgentsNotch",
            dependencies: ["AgentsNotchCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AgentsNotchHook",
            dependencies: ["AgentsNotchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AgentsNotchTests",
            dependencies: ["AgentsNotchCore", "AgentsNotch"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
