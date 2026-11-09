// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VideoEngine",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "VideoEngine", targets: ["VideoEngine"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "VideoEngine",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
            ],
            resources: [.copy("Resources/Templates")]
        ),
        .testTarget(
            name: "VideoEngineTests",
            dependencies: [
                "VideoEngine",
                .product(name: "Domain", package: "Domain"),
            ]
        ),
    ]
)
