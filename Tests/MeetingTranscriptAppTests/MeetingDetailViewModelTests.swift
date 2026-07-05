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

    func testGenerateSummaryDoesNotPublishWhenSelectedMeetingChanges() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let meetingA = Self.sampleDocument(id: "meeting-a", title: "Meeting A")
        let meetingB = Self.sampleDocument(id: "meeting-b", title: "Meeting B")
        try repository.save(meetingA)
        try repository.save(meetingB)
        let generator = SuspendedSummaryGenerator()
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: meetingA.meeting.id)
        let task = Task {
            await viewModel.generateSummary()
        }
        await generator.waitUntilRequested()

        viewModel.load(meetingId: meetingB.meeting.id)
        generator.resume(with: "# A 摘要")
        await task.value

        XCTAssertEqual(try repository.loadSummary(meetingId: meetingA.meeting.id), "# A 摘要")
        XCTAssertEqual(viewModel.document?.meeting.id, meetingB.meeting.id)
        XCTAssertNil(viewModel.summaryMarkdown)
        XCTAssertNotEqual(viewModel.summaryMarkdown, "# A 摘要")
    }

    func testLoadKeepsTranscriptWhenSummaryMarkdownIsCorrupt() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()
        try repository.save(document)
        let summaryURL = try repository.meetingDirectory(for: document.meeting.id).appendingPathComponent("summary.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: summaryURL)
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success(""))
        )

        viewModel.load(meetingId: document.meeting.id)

        XCTAssertEqual(viewModel.document?.meeting.id, document.meeting.id)
        XCTAssertNil(viewModel.summaryMarkdown)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private static func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func sampleDocument(
        id: String = "2026-07-04-1400-tgb-sit",
        title: String = "TGB SIT 進度會議"
    ) -> TranscriptDocument {
        TranscriptDocument(
            meeting: Meeting(
                id: id,
                title: title,
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

private final class SuspendedSummaryGenerator: CodexSummaryGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var requestedContinuation: CheckedContinuation<Void, Never>?
    private var summaryContinuation: CheckedContinuation<String, Error>?
    private var requestedDocumentsStorage: [TranscriptDocument] = []

    var requestedDocuments: [TranscriptDocument] {
        lock.lock()
        defer { lock.unlock() }
        return requestedDocumentsStorage
    }

    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            requestedDocumentsStorage.append(document)
            summaryContinuation = continuation
            let requestedContinuation = requestedContinuation
            self.requestedContinuation = nil
            lock.unlock()

            requestedContinuation?.resume()
        }
    }

    func waitUntilRequested() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if requestedDocumentsStorage.isEmpty {
                requestedContinuation = continuation
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func resume(with summary: String) {
        lock.lock()
        let summaryContinuation = summaryContinuation
        self.summaryContinuation = nil
        lock.unlock()

        summaryContinuation?.resume(returning: summary)
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
