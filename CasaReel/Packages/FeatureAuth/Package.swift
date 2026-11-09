// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureAuth",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeatureAuth", targets: ["FeatureAuth"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "FeatureAuth",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(
            name: "FeatureAuthTests",
            dependencies: ["FeatureAuth"]
        ),
    ]
)
