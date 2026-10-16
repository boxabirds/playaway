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
        .library(name: "PlayawayCore", targets: ["PlayawayCore"]),
        .library(name: "PlayawayLyrics", targets: ["PlayawayLyrics"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.1.1")
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
        // The lyrics experiment's engines: Apple's speech model, WhisperKit and a Core ML vocal separator. Kept out of
        // PlayawayCore so the core stays free of machine-learning frameworks; the core only sees timed words.
        .target(
            name: "PlayawayLyrics",
            dependencies: ["PlayawayCore", .product(name: "WhisperKit", package: "argmax-oss-swift")],
            path: "Sources/PlayawayLyrics",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Mac-only measurement of the lyrics engines on songs with known lyrics: `swift run lyrics-eval <folder>`.
        .executableTarget(
            name: "lyrics-eval",
            dependencies: ["PlayawayCore", "PlayawayLyrics"],
            path: "Sources/LyricsEval",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlayawayLyricsTests",
            dependencies: ["PlayawayLyrics", "PlayawayCore"],
            path: "Tests/PlayawayLyricsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlayawayCoreTests",
            dependencies: ["PlayawayCore"],
            path: "Tests/PlayawayCoreTests",
            resources: [.copy("Fixtures")],
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
