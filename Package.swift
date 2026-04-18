// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "lithepg",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "lithepg",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .testTarget(
            name: "lithepgTests",
            dependencies: ["lithepg"]
        ),
    ]
)
