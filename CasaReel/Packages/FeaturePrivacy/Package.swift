// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeaturePrivacy",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeaturePrivacy", targets: ["FeaturePrivacy"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "FeaturePrivacy",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(
            name: "FeaturePrivacyTests",
            dependencies: ["FeaturePrivacy"]
        ),
    ]
)
