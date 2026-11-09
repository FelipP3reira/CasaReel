// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeaturePhotos",
    defaultLocalization: "pt-BR",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeaturePhotos", targets: ["FeaturePhotos"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "FeaturePhotos",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FeaturePhotosTests",
            dependencies: [
                "FeaturePhotos",
                .product(name: "Domain", package: "Domain"),
            ]
        ),
    ]
)
