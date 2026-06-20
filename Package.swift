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
        .executable(name: "LithePGApp", targets: ["LithePGApp"]),
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
            dependencies: ["LithePGCore", "LithePGAppUI"]
        ),
        // UI module keeps the Sources/LithePGApp path so packaging scripts can
        // resolve LithePGApp.entitlements at its long-standing location.
        .target(
            name: "LithePGAppUI",
            dependencies: ["LithePGCore"],
            path: "Sources/LithePGApp",
            exclude: ["LithePGApp.entitlements"]
        ),
        // Thin launcher: the target name fixes the built binary name to
        // LithePGApp, which build_and_run.sh and package_verify.sh require.
        .executableTarget(
            name: "LithePGApp",
            dependencies: ["LithePGAppUI"],
            path: "Sources/LithePGAppMain"
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
            dependencies: ["LithePGAppUI"],
            swiftSettings: [.enableExperimentalFeature("Testing")]
        ),
        .testTarget(
            name: "LithePGAppUITests",
            dependencies: []
        ),
    ]
)
