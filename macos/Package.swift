// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AnkerCtl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AnkerCtl",
            path: "Sources/AnkerCtl"
        ),
    ]
)
