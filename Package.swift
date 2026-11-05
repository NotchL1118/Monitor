// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Monitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Monitor", targets: ["Monitor"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MonitorCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Monitor", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorAppTests", dependencies: ["Monitor", "MonitorCore"])
    ]
)
