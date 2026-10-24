// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SicGo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SicGo")
    ]
)
