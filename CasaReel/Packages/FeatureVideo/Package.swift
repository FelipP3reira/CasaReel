// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureVideo",
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
            ]
        ),
        .testTarget(
            name: "FeatureVideoTests",
            dependencies: ["FeatureVideo"]
        ),
    ]
)
