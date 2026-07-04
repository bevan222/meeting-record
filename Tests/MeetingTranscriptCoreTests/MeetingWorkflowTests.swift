import XCTest
@testable import MeetingTranscriptCore

final class MeetingWorkflowTests: XCTestCase {
    func testRunsMockTranscriptionDiarizationAndSpeakerRename() async throws {
        let meeting = Meeting(
            id: "2026-07-04-1400-tgb-sit",
            title: "TGB SIT 進度會議",
            recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
            durationSeconds: 22,
            language: "zh-TW",
            sourceAudio: "audio.m4a",
            status: .recorded
        )
        let workflow = MeetingWorkflow(
            transcriptionEngine: MockTranscriptionEngine(),
            diarizationEngine: MockDiarizationEngine(),
            assembler: TranscriptAssembler()
        )

        var document = try await workflow.buildTranscript(for: meeting, audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"))
        document = workflow.renameSpeaker("speaker_1", to: "Gavin", in: document)

        XCTAssertEqual(document.meeting.status, .speakerAttributed)
        XCTAssertEqual(document.speakers.first { $0.id == "speaker_1" }?.name, "Gavin")
        XCTAssertEqual(document.segments[0].speakerId, "speaker_1")
        XCTAssertEqual(document.segments.count, 3)
    }
}
