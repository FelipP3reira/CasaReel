// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Walk3DKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Walk3DKit", targets: ["Walk3DKit"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "Walk3DKit",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
            ]
        ),
        .testTarget(
            name: "Walk3DKitTests",
            dependencies: [
                "Walk3DKit",
                .product(name: "Domain", package: "Domain"),
            ]
        ),
    ]
)
