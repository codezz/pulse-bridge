// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
        .library(name: "PulseBLE", targets: ["PulseBLE"]),
    ],
    targets: [
        .target(name: "PulseKit", resources: [.process("Localizable.xcstrings")]),
        /// CoreBluetooth transport, shared by the iOS app and the macOS test tool.
        .target(name: "PulseBLE", dependencies: ["PulseKit"], resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"]),
    ]
)
