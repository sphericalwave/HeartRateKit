// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeartRateKit",
    platforms: [.iOS(.v16), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "HeartRateKit", targets: ["HeartRateKit"]),
    ],
    targets: [
        .target(name: "HeartRateKit"),
        .testTarget(name: "HeartRateKitTests", dependencies: ["HeartRateKit"]),
    ]
)
