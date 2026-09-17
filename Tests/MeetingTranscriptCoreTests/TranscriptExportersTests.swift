import XCTest
@testable import MeetingTranscriptCore

final class TranscriptExportersTests: XCTestCase {
    func testJSONExporterProducesDecodableTranscript() throws {
        let document = Self.sampleDocument()
        let data = try JSONTranscriptExporter().export(document)
        let decoded = try JSONDecoder.transcriptDecoder.decode(TranscriptDocument.self, from: data)

        XCTAssertEqual(decoded.meeting.id, document.meeting.id)
        XCTAssertEqual(decoded.segments.count, 2)
        XCTAssertEqual(decoded.speakers[0].label, "Speaker 1")
    }

    func testMarkdownExporterFormatsMetadataAndSegments() throws {
        let markdown = MarkdownTranscriptExporter().export(Self.sampleDocument())

        XCTAssertTrue(markdown.contains("# TGB SIT 進度會議逐字稿"))
        XCTAssertTrue(markdown.contains("- 時間：2026-07-04 14:00"))
        XCTAssertTrue(markdown.contains("- 長度：1 分鐘"))
        XCTAssertTrue(markdown.contains("- 語言：zh-TW"))
        XCTAssertTrue(markdown.contains("- 音檔：audio.m4a"))
        XCTAssertTrue(markdown.contains("[00:00:03] Gavin：今天先確認 SIT 測試範圍。"))
        XCTAssertTrue(markdown.contains("[00:00:08] Speaker 2：API 還有兩支沒測完。"))
    }

    private static func sampleDocument() -> TranscriptDocument {
        TranscriptDocument(
            meeting: Meeting(
                id: "2026-07-04-1400-tgb-sit",
                title: "TGB SIT 進度會議",
                recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
                durationSeconds: 60,
                language: "zh-TW",
                sourceAudio: "audio.m4a",
                status: .speakerAttributed
            ),
            speakers: [
                Speaker(id: "speaker_1", label: "Speaker 1", name: "Gavin"),
                Speaker(id: "speaker_2", label: "Speaker 2", name: nil)
            ],
            segments: [
                TranscriptSegment(id: "seg_0001", start: 3.2, end: 8.1, speakerId: "speaker_1", text: "今天先確認 SIT 測試範圍。", confidence: nil),
                TranscriptSegment(id: "seg_0002", start: 8.2, end: 15.0, speakerId: "speaker_2", text: "API 還有兩支沒測完。", confidence: nil)
            ]
        )
    }
}
