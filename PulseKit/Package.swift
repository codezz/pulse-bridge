// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
        .library(name: "PulseBLE", targets: ["PulseBLE"]),
    ],
    targets: [
        .target(name: "PulseKit"),
        /// CoreBluetooth transport, shared by the iOS app and the macOS test tool.
        .target(name: "PulseBLE", dependencies: ["PulseKit"]),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"]),
    ]
)
