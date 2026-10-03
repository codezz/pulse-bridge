// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pulse-sync",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../PulseKit")],
    targets: [
        .executableTarget(
            name: "pulse-sync",
            dependencies: [
                .product(name: "PulseKit", package: "PulseKit"),
                .product(name: "PulseBLE", package: "PulseKit"),
            ],
            // macOS requires a Bluetooth usage description, even for a command-line tool.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                "-Xlinker", Context.packageDirectory + "/Info.plist",
            ])]),
    ]
)
