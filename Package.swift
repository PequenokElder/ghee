// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GuitarMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "GuitarMonitor", path: "Sources/GuitarMonitor")
    ]
)
