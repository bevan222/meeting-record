import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

final class MeetingProcessingStateDisplayTests: XCTestCase {
    func testProcessingStatesUseReadableLabels() {
        XCTAssertEqual(MeetingProcessingState.recording.displayText, "錄音中")
        XCTAssertEqual(MeetingProcessingState.transcribing.displayText, "轉文字中...")
        XCTAssertEqual(MeetingProcessingState.diarizing.displayText, "講者標註中...")
        XCTAssertEqual(MeetingProcessingState.failed.displayText, "失敗")
    }

    func testProcessingAndFailureFlags() {
        XCTAssertTrue(MeetingProcessingState.transcribing.isProcessing)
        XCTAssertTrue(MeetingProcessingState.diarizing.isProcessing)
        XCTAssertFalse(MeetingProcessingState.speakerAttributed.isProcessing)
        XCTAssertTrue(MeetingProcessingState.failed.isFailure)
    }
}
