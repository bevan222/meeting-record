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
        XCTAssertTrue(buildScript.contains("swift build -c \"$BUILD_CONFIGURATION\" --arch arm64"))
        XCTAssertTrue(buildScript.contains("lipo -archs \"$EXECUTABLE\""))
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
        XCTAssertTrue(releaseDMGScript.contains("xattr -cr \"$app_path\""))
        XCTAssertTrue(releaseDMGScript.contains("\"$SCRIPT_DIR/verify-release-dmg.sh\" \"$DMG_PATH\""))
    }

    func testReleaseDMGScriptRetriesStagedSignatureVerificationWithoutRecheckingSourceApp() throws {
        let releaseDMGScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/build-release-dmg.sh")
        let releaseDMGScript = try String(contentsOf: releaseDMGScriptURL, encoding: .utf8)

        XCTAssertTrue(releaseDMGScript.contains("verify_app_signature()"))
        XCTAssertTrue(releaseDMGScript.contains("for _ in 1 2 3 4 5 6 7 8 9 10; do"))
        XCTAssertTrue(releaseDMGScript.contains("xattr -cr \"$app_path\""))
        XCTAssertTrue(releaseDMGScript.contains("verify_app_signature \"$STAGING_DIR/Meet Note.app\""))
        XCTAssertFalse(releaseDMGScript.contains("codesign --verify --deep --strict --verbose=4 \"$APP_DIR\""))
    }

    func testReleaseDMGVerifierRequiresDeploymentMetadataAndTestableCleanup() throws {
        let verifierScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/verify-release-dmg.sh")
        let verifierScript = try String(contentsOf: verifierScriptURL, encoding: .utf8)

        XCTAssertTrue(verifierScript.contains("VTOOL_COMMAND=\"${VTOOL_COMMAND:-vtool}\""))
        XCTAssertTrue(verifierScript.contains("minimum_macos=\"$(read_macos_deployment_target \"$EXECUTABLE\")\""))
        XCTAssertTrue(verifierScript.contains("DETACH_RETRIES=\"${DETACH_RETRIES:-3}\""))
        XCTAssertTrue(verifierScript.contains("for ((attempt = 1; attempt <= DETACH_RETRIES; attempt++))"))
        XCTAssertTrue(verifierScript.contains("if [[ \"${1:-}\" == \"--self-test\" ]]"))
        XCTAssertTrue(verifierScript.contains("finish_success()"))
        XCTAssertTrue(verifierScript.contains("finish_success \"$DMG_PATH\""))
        XCTAssertTrue(verifierScript.contains("cleanup_output"))
    }
}
