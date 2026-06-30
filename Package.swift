// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Picolo",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Picolo",
            path: "Sources/Picolo"
        )
    ]
)
