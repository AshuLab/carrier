// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SpikeSidebar",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "SpikeSidebar", path: "Sources")],
    swiftLanguageModes: [.v5]
)
