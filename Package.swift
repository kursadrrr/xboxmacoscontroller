// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XboxToolbarController",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "XboxToolbarController",
            path: "Sources/XboxToolbarController"
        )
    ]
)
