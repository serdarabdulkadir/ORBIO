// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EkosistemCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "EkosistemCore", targets: ["EkosistemCore"])],
    targets: [
        .target(name: "EkosistemCore"),
        .testTarget(name: "EkosistemCoreTests", dependencies: ["EkosistemCore"]),
    ]
)
