// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InfiniteBrain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "InfiniteBrain", targets: ["InfiniteBrain"])
    ],
    dependencies: [
        .package(path: "SharedLLMKit")
    ],
    targets: [
        .executableTarget(
            name: "InfiniteBrain",
            dependencies: [
                .product(name: "SharedLLMKit", package: "SharedLLMKit")
            ],
            path: "Sources/InfiniteBrain",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "InfiniteBrainTests",
            dependencies: ["InfiniteBrain"],
            path: "Tests/InfiniteBrainTests"
        )
    ]
)
