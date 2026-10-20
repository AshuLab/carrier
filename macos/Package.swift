// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Carrier",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CarrierCore"),
        .executableTarget(name: "Carrier", dependencies: ["CarrierCore"]),
        .testTarget(name: "CarrierCoreTests", dependencies: ["CarrierCore"]),
        .testTarget(name: "CarrierTests", dependencies: ["Carrier"]),
    ]
)
