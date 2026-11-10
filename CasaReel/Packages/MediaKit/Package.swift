// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MediaKit", targets: ["MediaKit"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "MediaKit",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
            ],
            // Depth Anything V2 Small (Apple's Core ML conversion, Apache-2.0), precompiled with `coremlcompiler`.
            resources: [.copy("Resources/DepthAnythingV2SmallF16P8.mlmodelc")]
        ),
        .testTarget(
            name: "MediaKitTests",
            dependencies: [
                "MediaKit",
                .product(name: "Domain", package: "Domain"),
            ]
        ),
    ]
)
