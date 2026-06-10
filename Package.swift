// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "lithepg",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LithePGCore", targets: ["LithePGCore"]),
        .executable(name: "lithepg", targets: ["lithepg"]),
        .executable(name: "lithepg-bench", targets: ["LithePGBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .target(
            name: "LithePGCore",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .executableTarget(
            name: "lithepg",
            dependencies: ["LithePGCore", "LithePGApp"]
        ),
        .target(
            name: "LithePGApp",
            dependencies: ["LithePGCore"],
            exclude: ["LithePGApp.entitlements"]
        ),
        .executableTarget(
            name: "LithePGBench",
            dependencies: ["LithePGCore"]
        ),
        .testTarget(
            name: "LithePGCoreTests",
            dependencies: ["LithePGCore"],
            swiftSettings: [.enableExperimentalFeature("Testing")]
        ),
        .testTarget(
            name: "LithePGAppTests",
            dependencies: ["LithePGApp"],
            swiftSettings: [.enableExperimentalFeature("Testing")]
        ),
        .testTarget(
            name: "LithePGAppUITests",
            dependencies: []
        ),
    ]
)
