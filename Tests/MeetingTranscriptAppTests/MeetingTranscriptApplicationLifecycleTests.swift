import AppKit
import XCTest
@testable import MeetingTranscriptApp

@MainActor
final class MeetingTranscriptApplicationLifecycleTests: XCTestCase {
    func testClosingLastWindowKeepsApplicationRunning() {
        let appDelegate = MeetingTranscriptApplicationDelegate()

        XCTAssertFalse(
            appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        )
    }
}
