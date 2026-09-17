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
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "1")
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
        XCTAssertTrue(buildScript.contains("${BUILD_CONFIGURATION:-debug}"))
    }

    func testReleaseDMGScriptPackagesTheInternalDistributionArtifacts() throws {
        let releaseDMGScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/build-release-dmg.sh")
        let releaseDMGScript = try String(contentsOf: releaseDMGScriptURL, encoding: .utf8)

        XCTAssertTrue(releaseDMGScript.contains(".build/dist/Meet Note.dmg"))
        XCTAssertTrue(releaseDMGScript.contains("ln -s /Applications"))
        XCTAssertTrue(releaseDMGScript.contains("BUILD_CONFIGURATION=release"))
        XCTAssertTrue(releaseDMGScript.contains("codesign --verify"))
        XCTAssertTrue(releaseDMGScript.contains("hdiutil create"))
        XCTAssertTrue(releaseDMGScript.contains("${TMPDIR:-/tmp}/meet-note-dmg.XXXXXX"))
        XCTAssertTrue(releaseDMGScript.contains("xattr -cr \"$STAGING_DIR/Meet Note.app\""))
    }
}
