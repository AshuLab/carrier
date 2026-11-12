// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Carrier",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.3"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1"),
    ],
    targets: [
        .target(name: "CarrierCore", resources: [.copy("Resources/FileIcons"), .copy("Resources/ProviderIcons")]),
        .executableTarget(name: "Carrier", dependencies: [
            "CarrierCore",
            .product(name: "Sparkle", package: "Sparkle"),
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
        ]),
        .testTarget(name: "CarrierCoreTests", dependencies: ["CarrierCore"]),
        .testTarget(name: "CarrierTests", dependencies: ["Carrier"]),
    ],
    swiftLanguageModes: [.v5]
)
