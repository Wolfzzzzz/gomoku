// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gomoku",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Gomoku", path: "Sources/Gomoku")
    ]
)
