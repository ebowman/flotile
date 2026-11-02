// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FloTile",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FloTileCore", targets: ["FloTileCore"]),
    ],
    targets: [
        .target(name: "FloTileCore"),
        .testTarget(name: "FloTileCoreTests", dependencies: ["FloTileCore"]),
    ],
    swiftLanguageModes: [.v6]
)
