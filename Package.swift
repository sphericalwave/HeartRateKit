// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeartRateKit",
    platforms: [.iOS(.v16), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "HeartRateCore", targets: ["HeartRateCore"]),
        .library(name: "HeartRateKit", targets: ["HeartRateKit"]),
    ],
    targets: [
        .target(name: "HeartRateCore"),
        .testTarget(name: "HeartRateCoreTests", dependencies: ["HeartRateCore"]),
        .target(name: "HeartRateKit", dependencies: ["HeartRateCore"]),
        .testTarget(name: "HeartRateKitTests", dependencies: ["HeartRateKit"]),
        // Swift 6 mode: compile-checks that @MainActor owners can start a source.
        .testTarget(name: "HeartRateConcurrencyTests", dependencies: ["HeartRateKit"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ],
    swiftLanguageModes: [.v5]
)
