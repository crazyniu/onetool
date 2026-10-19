// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OneTool",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OneTool", path: "Sources", exclude: ["FinderExtension"]),
    ]
)
