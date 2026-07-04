import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModelTests: XCTestCase {
    func testUpdateMeetingTitlePersistsTranscriptMetadataAndMarkdown() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let viewModel = MeetingDetailViewModel(repository: repository, markdownExporter: MarkdownTranscriptExporter())

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        let updatedTitle = viewModel.updateMeetingTitle("TGB SIT API 測試會議")

        let loaded = try repository.loadTranscript(meetingId: "2026-07-04-1400-tgb-sit")
        let metadata = try repository.listMeetings().first
        let markdownURL = root.appendingPathComponent("2026-07-04-1400-tgb-sit/transcript.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)

        XCTAssertEqual(updatedTitle, "TGB SIT API 測試會議")
        XCTAssertEqual(viewModel.document?.meeting.title, "TGB SIT API 測試會議")
        XCTAssertEqual(loaded.meeting.title, "TGB SIT API 測試會議")
        XCTAssertEqual(metadata?.title, "TGB SIT API 測試會議")
        XCTAssertTrue(markdown.contains("# TGB SIT API 測試會議逐字稿"))
    }

    func testUpdateMeetingTitleUsesFallbackForBlankTitle() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let viewModel = MeetingDetailViewModel(repository: repository, markdownExporter: MarkdownTranscriptExporter())

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        let updatedTitle = viewModel.updateMeetingTitle("   ")

        let loaded = try repository.loadTranscript(meetingId: "2026-07-04-1400-tgb-sit")
        XCTAssertEqual(updatedTitle, "Untitled Meeting")
        XCTAssertEqual(viewModel.document?.meeting.title, "Untitled Meeting")
        XCTAssertEqual(loaded.meeting.title, "Untitled Meeting")
    }

    private static func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func sampleDocument() -> TranscriptDocument {
        TranscriptDocument(
            meeting: Meeting(
                id: "2026-07-04-1400-tgb-sit",
                title: "TGB SIT 進度會議",
                recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
                durationSeconds: 65,
                language: "zh-TW",
                sourceAudio: "audio.m4a",
                status: .speakerAttributed
            ),
            speakers: [Speaker(id: "speaker_1", label: "Speaker 1", name: nil)],
            segments: [TranscriptSegment(id: "seg_0001", start: 3, end: 8, speakerId: "speaker_1", text: "今天先確認 SIT 測試範圍。", confidence: nil)]
        )
    }
}
