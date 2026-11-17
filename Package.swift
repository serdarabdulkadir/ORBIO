// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EkosistemCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "EkosistemCore", targets: ["EkosistemCore"]),
        .executable(name: "BTEkosistem", targets: ["BTEkosistem"]),
    ],
    targets: [
        .target(name: "EkosistemCore"),
        .executableTarget(
            name: "BTEkosistem",
            dependencies: ["EkosistemCore"],
            exclude: ["Info.plist"],
            // SPM calistirilabiliri paket degildir: izin metni (TCC) icin Info.plist ikiliye gomulur.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist", "-Xlinker", "Sources/BTEkosistem/Info.plist",
            ])]
        ),
        .testTarget(name: "EkosistemCoreTests", dependencies: ["EkosistemCore"]),
    ]
)
