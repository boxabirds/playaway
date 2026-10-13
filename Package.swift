// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalPlayer",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .executable(name: "LocalPlayer", targets: ["LocalPlayer"]),
        .library(name: "PlayawayCore", targets: ["PlayawayCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        // Shared by the Mac and iPhone apps. No AppKit or UIKit here. Cross-package consumers would need `public`
        // (the `package` access level only reaches targets of this package; unverified outside it).
        .target(
            name: "PlayawayCore",
            path: "Sources/PlayawayCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "LocalPlayer",
            dependencies: ["PlayawayCore", "Sparkle"],
            path: "Sources/LocalPlayer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlayawayCoreTests",
            dependencies: ["PlayawayCore"],
            path: "Tests/PlayawayCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LocalPlayerTests",
            dependencies: ["LocalPlayer", "PlayawayCore"],
            path: "Tests/LocalPlayerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
