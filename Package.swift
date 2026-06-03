// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InfiniteBrain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "InfiniteBrain", targets: ["InfiniteBrain"]),
        .executable(name: "infb", targets: ["InfiniteBrainCLI"]),
        .library(name: "InfiniteBrainCore", targets: ["InfiniteBrainCore"]),
    ],
    dependencies: [
        .package(path: "SharedLLMKit"),
        .package(url: "https://github.com/dnsmalla/graph-kit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "InfiniteBrainCore",
            dependencies: [
                .product(name: "SharedLLMKit", package: "SharedLLMKit"),
                .product(name: "GraphKit", package: "graph-kit"),
            ],
            path: "Sources/InfiniteBrainCore",
            resources: [
                .copy("Resources/skills"),
                .copy("Resources/rules"),
                .copy("Resources/web"),
            ]
        ),
        .executableTarget(
            name: "InfiniteBrain",
            dependencies: ["InfiniteBrainCore"],
            path: "Sources/InfiniteBrain"
        ),
        .executableTarget(
            name: "InfiniteBrainCLI",
            dependencies: ["InfiniteBrainCore"],
            path: "Sources/InfiniteBrainCLI"
        ),
        .testTarget(
            name: "InfiniteBrainTests",
            dependencies: ["InfiniteBrainCore"],
            path: "Tests/InfiniteBrainTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
