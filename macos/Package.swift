// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Carrier",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CarrierCore"),
        .executableTarget(name: "Carrier", dependencies: ["CarrierCore"]),
        .testTarget(name: "CarrierCoreTests", dependencies: ["CarrierCore"]),
        .testTarget(name: "CarrierTests", dependencies: ["Carrier"]),
    ],
    swiftLanguageModes: [.v5]
)
