// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingTranscriptApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MeetingTranscriptCore", targets: ["MeetingTranscriptCore"]),
        .executable(name: "MeetingTranscriptApp", targets: ["MeetingTranscriptApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "MeetingTranscriptCore",
            path: "Sources/MeetingTranscriptCore"
        ),
        .executableTarget(
            name: "MeetingTranscriptApp",
            dependencies: [
                "MeetingTranscriptCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift")
            ],
            path: "MeetingTranscriptApp",
            exclude: ["Resources/Info.plist", "Resources/MeetingTranscriptApp.entitlements"]
        ),
        .testTarget(
            name: "MeetingTranscriptCoreTests",
            dependencies: ["MeetingTranscriptCore"],
            path: "Tests/MeetingTranscriptCoreTests"
        ),
        .testTarget(
            name: "MeetingTranscriptAppTests",
            dependencies: ["MeetingTranscriptApp"],
            path: "Tests/MeetingTranscriptAppTests"
        )
    ]
)
