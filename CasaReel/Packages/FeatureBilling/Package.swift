// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureBilling",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeatureBilling", targets: ["FeatureBilling"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "FeatureBilling",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(
            name: "FeatureBillingTests",
            dependencies: ["FeatureBilling"]
        ),
    ]
)
