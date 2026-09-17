import XCTest

final class EntitlementsTests: XCTestCase {
    func testAppSandboxIsNotEnabledBecauseCodexCLIRequiresUserCodexState() throws {
        let entitlementsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("MeetingTranscriptApp/Resources/MeetingTranscriptApp.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertNotEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
    }
}
