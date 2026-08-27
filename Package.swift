// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandBar", targets: ["IslandBar"])
    ],
    targets: [
        .executableTarget(
            name: "IslandBar",
            path: "Sources/IslandBar",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
