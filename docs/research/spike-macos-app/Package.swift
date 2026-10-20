// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpikeCarrier",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "SpikeCarrier", path: "Sources")]
)
