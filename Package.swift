// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalPlayer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "LocalPlayer", targets: ["LocalPlayer"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "LocalPlayer",
            dependencies: ["Sparkle"],
            path: "Sources/LocalPlayer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LocalPlayerTests",
            dependencies: ["LocalPlayer"],
            path: "Tests/LocalPlayerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
