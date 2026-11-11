// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CasaReelWalk3DRenderer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "casareel-walk3d-renderer", targets: ["CasaReelWalk3DRenderer"])],
    targets: [.executableTarget(name: "CasaReelWalk3DRenderer")]
)
