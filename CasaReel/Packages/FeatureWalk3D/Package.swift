// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureWalk3D",
    defaultLocalization: "pt-BR",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeatureWalk3D", targets: ["FeatureWalk3D"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
        // Only for its event and result types; the app injects the actual exporter and renderer.
        .package(path: "../Walk3DKit"),
    ],
    targets: [
        .target(
            name: "FeatureWalk3D",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Walk3DKit", package: "Walk3DKit"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FeatureWalk3DTests",
            dependencies: [
                "FeatureWalk3D",
                .product(name: "Walk3DKit", package: "Walk3DKit"),
            ]
        ),
    ]
)
