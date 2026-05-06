// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedLLMKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SharedLLMKit", targets: ["SharedLLMKit"])
    ],
    targets: [
        .target(
            name: "SharedLLMKit",
            path: "Sources/SharedLLMKit"
        ),
        .testTarget(
            name: "SharedLLMKitTests",
            dependencies: ["SharedLLMKit"],
            path: "Tests/SharedLLMKitTests"
        )
    ]
)
