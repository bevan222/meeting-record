import XCTest

final class BrandingTests: XCTestCase {
    func testInfoPlistUsesMeetNoteForUserVisibleBranding() throws {
        let infoPlistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("MeetingTranscriptApp/Resources/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Meet Note")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Meet Note")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "MeetingTranscriptApp")
        XCTAssertEqual(
            plist["NSMicrophoneUsageDescription"] as? String,
            "Meet Note records meeting audio locally to create transcripts."
        )
    }

    func testBuildScriptCreatesMeetNoteAppBundle() throws {
        let buildScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/build-macos-app.sh")
        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)

        XCTAssertTrue(buildScript.contains("APP_DIR=\".build/app/Meet Note.app\""))
    }
}
