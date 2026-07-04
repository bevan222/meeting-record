// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingTranscriptApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MeetingTranscriptCore", targets: ["MeetingTranscriptCore"]),
        .executable(name: "MeetingTranscriptApp", targets: ["MeetingTranscriptApp"])
    ],
    targets: [
        .target(
            name: "MeetingTranscriptCore",
            path: "Sources/MeetingTranscriptCore"
        ),
        .executableTarget(
            name: "MeetingTranscriptApp",
            dependencies: ["MeetingTranscriptCore"],
            path: "MeetingTranscriptApp",
            exclude: ["Resources/Info.plist", "Resources/MeetingTranscriptApp.entitlements"]
        ),
        .testTarget(
            name: "MeetingTranscriptCoreTests",
            dependencies: ["MeetingTranscriptCore"],
            path: "Tests/MeetingTranscriptCoreTests"
        )
    ]
)
