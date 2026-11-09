// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MediaKit", targets: ["MediaKit"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "MediaKit",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
            ]
        ),
        .testTarget(
            name: "MediaKitTests",
            dependencies: ["MediaKit"]
        ),
    ]
)
