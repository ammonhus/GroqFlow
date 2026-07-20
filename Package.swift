// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GroqFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GroqFlow", targets: ["GroqFlow"]),
        .library(name: "GroqFlowKit", targets: ["GroqFlowKit"]),
    ],
    targets: [
        .target(
            name: "GroqFlowKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "GroqFlow",
            dependencies: ["GroqFlowKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GroqFlowKitTests",
            dependencies: ["GroqFlowKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
