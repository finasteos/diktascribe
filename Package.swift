// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LAGA-Ideas-Recorder",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LAGA-Ideas-Recorder", targets: ["LAGA-Ideas-Recorder"])
    ],
    dependencies: [
        // AudioKit for audio processing
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.0"),

        // Swift-Whisper for real-time transcription
        .package(url: "https://github.com/ggerganov/whisper.swift", from: "1.0.0"),

        // MarkdownUI for rich text display
        .package(url: "https://github.com/gonzalezreal/MarkdownUI", from: "2.0.0"),

        // SPIndicator for toast notifications
        .package(url: "https://github.com/ivanvorobei/SPIndicator", from: "1.0.0"),

        // SwiftUI-Introspect for advanced UI access
        .package(url: "https://github.com/siteline/SwiftUI-Introspect", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "LAGA-Ideas-Recorder",
            dependencies: [
                "AudioKit",
                "whisper.swift",
                "MarkdownUI",
                "SPIndicator",
                "SwiftUI-Introspect"
            ],
            path: "SwiftUI"
        )
    ],
    swiftLanguageVersions: [.v5]
)
