// swift-tools-version:5.10
// Als-Dan voor de Mac. Bouwen en starten: ./build.sh (maakt build/Als-Dan.app). Testen: swift test.
import PackageDescription

let package = Package(
    name: "AlsDan",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AlsDanCore"),
        .executableTarget(name: "AlsDan", dependencies: ["AlsDanCore"]),
        .testTarget(name: "AlsDanCoreTests", dependencies: ["AlsDanCore"]),
    ]
)
