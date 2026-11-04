// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DriftwallCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DriftwallCore", targets: ["DriftwallCore"]),
    ],
    targets: [
        .target(
            name: "DriftwallCore",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "DriftwallCoreTests",
            dependencies: ["DriftwallCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
