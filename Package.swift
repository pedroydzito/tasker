// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tasker",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "Tasker", path: "Sources/Tasker")
    ]
)
