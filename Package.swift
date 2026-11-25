// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GoTime",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GoTime", path: "Sources/GoTime")
    ]
)
