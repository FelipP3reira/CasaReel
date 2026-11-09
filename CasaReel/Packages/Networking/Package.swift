// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../SecurityKit"),
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: [
                .product(name: "Domain", package: "Domain"),
                .product(name: "SecurityKit", package: "SecurityKit"),
            ]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "Networking",
                .product(name: "Domain", package: "Domain"),
                .product(name: "SecurityKit", package: "SecurityKit"),
            ]
        ),
    ]
)
