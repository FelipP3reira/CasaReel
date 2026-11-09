// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureProperties",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeatureProperties", targets: ["FeatureProperties"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "FeatureProperties",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(
            name: "FeaturePropertiesTests",
            dependencies: ["FeatureProperties"]
        ),
    ]
)
