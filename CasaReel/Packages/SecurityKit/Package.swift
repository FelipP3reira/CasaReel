// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SecurityKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "SecurityKit",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
            ]
        ),
        .testTarget(
            name: "SecurityKitTests",
            dependencies: ["SecurityKit"]
        ),
    ]
)
