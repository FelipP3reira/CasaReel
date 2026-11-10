// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureVideo",
    defaultLocalization: "pt-BR",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeatureVideo", targets: ["FeatureVideo"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "FeatureVideo",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FeatureVideoTests",
            dependencies: [
                "FeatureVideo",
                .product(name: "Domain", package: "Domain"),
            ]
        ),
    ]
)
