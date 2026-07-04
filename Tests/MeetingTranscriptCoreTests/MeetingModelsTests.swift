import XCTest
@testable import MeetingTranscriptCore

final class MeetingModelsTests: XCTestCase {
    func testTranscriptDocumentRoundTripsThroughJSON() throws {
        let document = TranscriptDocument(
            meeting: Meeting(
                id: "2026-07-04-1400-tgb-sit",
                title: "TGB SIT 進度會議",
                recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
                durationSeconds: 3600,
                language: "zh-TW",
                sourceAudio: "audio.m4a",
                status: .speakerAttributed
            ),
            speakers: [
                Speaker(id: "speaker_1", label: "Speaker 1", name: nil),
                Speaker(id: "speaker_2", label: "Speaker 2", name: "Gavin")
            ],
            segments: [
                TranscriptSegment(id: "seg_0001", start: 3.2, end: 8.1, speakerId: "speaker_1", text: "今天先確認 SIT 測試範圍。", confidence: nil)
            ]
        )

        let encoder = JSONEncoder.transcriptEncoder
        let decoder = JSONDecoder.transcriptDecoder
        let data = try encoder.encode(document)
        let decoded = try decoder.decode(TranscriptDocument.self, from: data)

        XCTAssertEqual(decoded.meeting.id, "2026-07-04-1400-tgb-sit")
        XCTAssertEqual(decoded.meeting.status, .speakerAttributed)
        XCTAssertEqual(decoded.speakers[1].displayName, "Gavin")
        XCTAssertEqual(decoded.segments[0].speakerId, "speaker_1")
        XCTAssertEqual(decoded.segments[0].text, "今天先確認 SIT 測試範圍。")
    }

    func testSpeakerDisplayNameUsesNameBeforeLabel() {
        XCTAssertEqual(Speaker(id: "speaker_1", label: "Speaker 1", name: "Gavin").displayName, "Gavin")
        XCTAssertEqual(Speaker(id: "speaker_1", label: "Speaker 1", name: nil).displayName, "Speaker 1")
        XCTAssertEqual(Speaker(id: "speaker_1", label: "Speaker 1", name: "").displayName, "Speaker 1")
    }
}
