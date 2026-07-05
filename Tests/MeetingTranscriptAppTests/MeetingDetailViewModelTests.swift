import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModelTests: XCTestCase {
    func testUpdateMeetingTitlePersistsTranscriptMetadataAndMarkdown() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success(""))
        )

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
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success(""))
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        let updatedTitle = viewModel.updateMeetingTitle("   ")

        let loaded = try repository.loadTranscript(meetingId: "2026-07-04-1400-tgb-sit")
        XCTAssertEqual(updatedTitle, "Untitled Meeting")
        XCTAssertEqual(viewModel.document?.meeting.title, "Untitled Meeting")
        XCTAssertEqual(loaded.meeting.title, "Untitled Meeting")
    }

    func testLoadReadsExistingSummaryMarkdown() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        try repository.saveSummary("# 舊摘要", meetingId: "2026-07-04-1400-tgb-sit")
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success(""))
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")

        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
    }

    func testGenerateSummarySavesPublishesAndUsesLatestTranscript() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let expectedSummary = "# 摘要\n\n- 決議：開始 SIT。"
        let generator = FakeSummaryGenerator(mode: .success(expectedSummary))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        viewModel.updateMeetingTitle("TGB SIT API 測試會議")
        await viewModel.generateSummary()

        XCTAssertEqual(try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit"), expectedSummary)
        XCTAssertEqual(viewModel.summaryMarkdown, expectedSummary)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isGeneratingSummary)
        XCTAssertEqual(generator.requestedDocuments.first?.meeting.title, "TGB SIT API 測試會議")
    }

    func testGenerateSummaryFailureKeepsExistingSummary() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        try repository.saveSummary("# 舊摘要", meetingId: "2026-07-04-1400-tgb-sit")
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .failure(TestSummaryError.failed))
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        await viewModel.generateSummary()

        XCTAssertEqual(try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit"), "# 舊摘要")
        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
        XCTAssertEqual(viewModel.errorMessage, "summary failed")
        XCTAssertFalse(viewModel.isGeneratingSummary)
    }

    func testGenerateSummaryRefusesDocumentWithoutSegments() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        var document = Self.sampleDocument()
        document.segments = []
        try repository.save(document)
        let generator = FakeSummaryGenerator(mode: .success("# 摘要"))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        await viewModel.generateSummary()

        XCTAssertNil(try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit"))
        XCTAssertNil(viewModel.summaryMarkdown)
        XCTAssertEqual(viewModel.errorMessage, "No transcript segments are available for summary.")
        XCTAssertTrue(generator.requestedDocuments.isEmpty)
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

private final class FakeSummaryGenerator: CodexSummaryGenerating, @unchecked Sendable {
    enum Mode {
        case success(String)
        case failure(Error)
    }

    private let mode: Mode
    private(set) var requestedDocuments: [TranscriptDocument] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String {
        requestedDocuments.append(document)
        switch mode {
        case .success(let summary):
            return summary
        case .failure(let error):
            throw error
        }
    }
}

private enum TestSummaryError: LocalizedError {
    case failed

    var errorDescription: String? {
        "summary failed"
    }
}
