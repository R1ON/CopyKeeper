// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopyPaster",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CopyPaster",
            path: "Sources/CopyPaster"
        )
    ]
)
