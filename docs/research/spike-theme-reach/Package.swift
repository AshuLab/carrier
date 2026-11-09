// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SpikeThemeReach",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "SpikeThemeReach", path: "Sources")],
    swiftLanguageModes: [.v5]
)
