import Darwin
import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModelTests: XCTestCase {
    func testAnotherProviderCanRunAfterForcedCancellationConfirmsProcessExit() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()
        try repository.save(document)
        let fixture = try IgnoringTerminationSummaryGenerator()
        defer { fixture.cleanUp() }
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            codexSummaryGenerator: fixture,
            claudeSummaryGenerator: FakeSummaryGenerator(mode: .success("# New summary"))
        )
        viewModel.load(meetingId: document.meeting.id)
        let task = Task { await viewModel.generateSummary(using: .codex) }
        defer { task.cancel() }
        let pid = try await fixture.waitUntilRunning()

        viewModel.load(meetingId: document.meeting.id)
        XCTAssertEqual(viewModel.activeSummaryProvider, .codex)
        XCTAssertFalse(viewModel.canGenerateSummary)
        await viewModel.generateSummary(using: .claude)
        XCTAssertNil(viewModel.summaryMarkdown)

        await waitForSummaryTask(task)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        XCTAssertTrue(viewModel.canGenerateSummary)
        await viewModel.generateSummary(using: .claude)
        XCTAssertEqual(viewModel.summaryMarkdown, "# New summary")
        XCTAssertEqual(try repository.loadSummary(meetingId: document.meeting.id), "# New summary")
    }

    func testSuccessfulSegmentEditInvalidatesActiveSummary() async throws {
        try await assertSummaryAfterEdit(invalidated: true) { viewModel in
            viewModel.updateSegmentText(segmentId: "seg_0001", text: "Corrected transcript")
        }
    }

    func testSuccessfulSpeakerRenameInvalidatesActiveSummary() async throws {
        try await assertSummaryAfterEdit(invalidated: true) { viewModel in
            viewModel.renameSpeaker(speakerId: "speaker_1", name: "Alice")
        }
    }

    func testSuccessfulTitleChangeInvalidatesActiveSummary() async throws {
        try await assertSummaryAfterEdit(invalidated: true) { viewModel in
            XCTAssertEqual(viewModel.updateMeetingTitle("Revised meeting"), "Revised meeting")
        }
    }

    func testNoOpEditsDoNotInvalidateActiveSummary() async throws {
        try await assertSummaryAfterEdit(invalidated: false) { viewModel in
            let document = viewModel.document!
            viewModel.updateSegmentText(segmentId: "seg_0001", text: document.segments[0].text)
            viewModel.updateSegmentText(segmentId: "missing", text: "Not an edit")
            viewModel.renameSpeaker(speakerId: "speaker_1", name: "  ")
            viewModel.renameSpeaker(speakerId: "missing", name: "Not an edit")
            viewModel.updateMeetingTitle("  \(document.meeting.title)  ")
        }
    }

    func testExportsDoNotInvalidateActiveSummary() async throws {
        try await assertSummaryAfterEdit(invalidated: false) { viewModel in
            viewModel.exportJSON()
            viewModel.exportMarkdown()
        }
    }

    func testFailedEditsDoNotInvalidateActiveSummary() async throws {
        try await assertSummaryAfterEdit(invalidated: false) { viewModel in
            let directory = try XCTUnwrap(viewModel.meetingFolderURL())
            let transcriptURL = directory.appendingPathComponent("transcript.json")
            let originalData = try Data(contentsOf: transcriptURL)
            try FileManager.default.removeItem(at: transcriptURL)
            try FileManager.default.createDirectory(at: transcriptURL, withIntermediateDirectories: false)
            defer {
                try? FileManager.default.removeItem(at: transcriptURL)
                try? originalData.write(to: transcriptURL)
            }
            let originalDocument = viewModel.document
            viewModel.updateSegmentText(segmentId: "seg_0001", text: "Cannot save")
            XCTAssertNotNil(viewModel.errorMessage)
            viewModel.renameSpeaker(speakerId: "speaker_1", name: "Cannot save")
            XCTAssertNotNil(viewModel.errorMessage)
            XCTAssertNil(viewModel.updateMeetingTitle("Cannot save"))
            XCTAssertNotNil(viewModel.errorMessage)
            XCTAssertEqual(viewModel.document, originalDocument)
        }
    }

    private func assertSummaryAfterEdit(
        invalidated: Bool,
        edit: (MeetingDetailViewModel) throws -> Void
    ) async throws {
        for provider in [SummaryProvider.codex, .claude] {
            let root = try Self.makeTemporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let repository = FileMeetingRepository(rootDirectory: root)
            let document = Self.sampleDocument()
            try repository.save(document)
            try repository.saveSummary("# Existing summary", meetingId: document.meeting.id)
            let generator = SuspendedSummaryGenerator()
            let viewModel = MeetingDetailViewModel(
                repository: repository,
                markdownExporter: MarkdownTranscriptExporter(),
                summaryGenerator: generator
            )
            viewModel.load(meetingId: document.meeting.id)
            let task = Task { await viewModel.generateSummary(using: provider) }
            defer {
                task.cancel()
                generator.resume(throwing: CancellationError())
            }
            await generator.waitUntilRequested()
            try edit(viewModel)
            XCTAssertEqual(viewModel.activeSummaryProvider, provider)
            XCTAssertFalse(viewModel.canGenerateSummary)
            generator.resume(with: "# Generated summary")
            await waitForSummaryTask(task)

            let expected = invalidated ? "# Existing summary" : "# Generated summary"
            XCTAssertEqual(try repository.loadSummary(meetingId: document.meeting.id), expected)
            XCTAssertEqual(viewModel.summaryMarkdown, expected)
            XCTAssertTrue(viewModel.canGenerateSummary)
            XCTAssertNil(viewModel.errorMessage)
        }
    }

    func testExportJSONWritesNamedCopyUsingMeetingTitleAndRecordedDate() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()
        try repository.save(document)
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success(""))
        )

        viewModel.load(meetingId: document.meeting.id)
        viewModel.exportJSON()

        let exportURL = root
            .appendingPathComponent(document.meeting.id)
            .appendingPathComponent("TGB SIT 進度會議_20260704.json")
        let exportedData = try Data(contentsOf: exportURL)
        let exportedDocument = try JSONDecoder.transcriptDecoder.decode(TranscriptDocument.self, from: exportedData)

        XCTAssertEqual(exportedDocument, document)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testExportMarkdownSanitizesTitleInNamedCopy() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument(title: "TGB/SIT:進度會議")
        try repository.save(document)
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success(""))
        )

        viewModel.load(meetingId: document.meeting.id)
        viewModel.exportMarkdown()

        let exportURL = root
            .appendingPathComponent(document.meeting.id)
            .appendingPathComponent("TGB_SIT_進度會議_20260704.md")
        let markdown = try String(contentsOf: exportURL, encoding: .utf8)

        XCTAssertTrue(markdown.contains("# TGB/SIT:進度會議逐字稿"))
        XCTAssertNil(viewModel.errorMessage)
    }

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

    func testGenerateSummaryRoutesClaudeRequestOnlyToClaudeGenerator() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let codex = FakeSummaryGenerator(mode: .success("# Codex 摘要"))
        let claude = FakeSummaryGenerator(mode: .success("# Claude 摘要"))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            codexSummaryGenerator: codex,
            claudeSummaryGenerator: claude
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        await viewModel.generateSummary(using: .claude)

        XCTAssertEqual(claude.requestedDocuments.count, 1)
        XCTAssertEqual(codex.requestedDocuments.count, 0)
        XCTAssertNil(viewModel.activeSummaryProvider)
        XCTAssertEqual(viewModel.summaryMarkdown, "# Claude 摘要")
    }

    func testGenerateSummaryRefusesSecondProviderWhileFirstProviderRuns() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let codex = SuspendedSummaryGenerator()
        let claude = FakeSummaryGenerator(mode: .success("# Claude 摘要"))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            codexSummaryGenerator: codex,
            claudeSummaryGenerator: claude
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        let task = Task {
            await viewModel.generateSummary(using: .codex)
        }
        await codex.waitUntilRequested()
        await viewModel.generateSummary(using: .claude)

        XCTAssertEqual(viewModel.activeSummaryProvider, .codex)
        XCTAssertEqual(claude.requestedDocuments.count, 0)

        codex.resume(with: "# Codex 摘要")
        await waitForSummaryTask(task)

        XCTAssertNil(viewModel.activeSummaryProvider)
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

    func testCancelledSummaryPreservesExistingSummary() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()
        try repository.save(document)
        try repository.saveSummary("# 舊摘要", meetingId: document.meeting.id)
        let generator = SuspendedSummaryGenerator()
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: document.meeting.id)
        let task = Task {
            await viewModel.generateSummary(using: .codex)
        }
        await generator.waitUntilRequested()
        task.cancel()
        generator.resume(with: "# 新摘要")
        await waitForSummaryTask(task)

        XCTAssertEqual(try repository.loadSummary(meetingId: document.meeting.id), "# 舊摘要")
        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSameMeetingReloadRejectsCompletedStaleSummary() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()
        try repository.save(document)
        try repository.saveSummary("# 舊摘要", meetingId: document.meeting.id)
        let generator = FakeSummaryGenerator(mode: .success("# Stale summary"))
        let gate = SummaryResultPublicationGate()
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            codexSummaryGenerator: generator,
            claudeSummaryGenerator: generator,
            summaryResult: gate.value
        )
        let meetingID = document.meeting.id
        viewModel.load(meetingId: meetingID)
        let task = Task {
            await viewModel.generateSummary()
        }
        await gate.waitUntilCompleted()
        viewModel.load(meetingId: meetingID)
        gate.allowPublication.fulfill()
        await waitForSummaryTask(task)

        XCTAssertEqual(try repository.loadSummary(meetingId: meetingID), "# 舊摘要")
        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testMeetingRoundTripRejectsCompletedStaleSummary() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let meetingA = Self.sampleDocument(id: "meeting-a", title: "Meeting A")
        let meetingB = Self.sampleDocument(id: "meeting-b", title: "Meeting B")
        try repository.save(meetingA)
        try repository.save(meetingB)
        try repository.saveSummary("# A 舊摘要", meetingId: meetingA.meeting.id)
        let generator = FakeSummaryGenerator(mode: .success("# Stale summary"))
        let gate = SummaryResultPublicationGate()
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            codexSummaryGenerator: generator,
            claudeSummaryGenerator: generator,
            summaryResult: gate.value
        )
        viewModel.load(meetingId: meetingA.meeting.id)
        let task = Task {
            await viewModel.generateSummary()
        }
        await gate.waitUntilCompleted()
        viewModel.load(meetingId: meetingB.meeting.id)
        viewModel.load(meetingId: meetingA.meeting.id)
        gate.allowPublication.fulfill()
        await waitForSummaryTask(task)

        XCTAssertEqual(try repository.loadSummary(meetingId: meetingA.meeting.id), "# A 舊摘要")
        XCTAssertEqual(viewModel.document?.meeting.id, meetingA.meeting.id)
        XCTAssertEqual(viewModel.summaryMarkdown, "# A 舊摘要")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadKeepsProviderLockUntilCancelledGeneratorFinishes() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let meetingA = Self.sampleDocument(id: "meeting-a", title: "Meeting A")
        let meetingB = Self.sampleDocument(id: "meeting-b", title: "Meeting B")
        try repository.save(meetingA)
        try repository.save(meetingB)
        let codex = SuspendedSummaryGenerator()
        let claude = FakeSummaryGenerator(mode: .success("# Claude 摘要"))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            codexSummaryGenerator: codex,
            claudeSummaryGenerator: claude
        )

        viewModel.load(meetingId: meetingA.meeting.id)
        let task = Task {
            await viewModel.generateSummary(using: .codex)
        }
        await codex.waitUntilRequested()

        viewModel.load(meetingId: meetingB.meeting.id)
        await viewModel.generateSummary(using: .claude)

        XCTAssertEqual(viewModel.activeSummaryProvider, .codex)
        XCTAssertEqual(claude.requestedDocuments.count, 0)

        codex.resume(with: "# Codex 摘要")
        await waitForSummaryTask(task)
        await viewModel.generateSummary(using: .claude)

        XCTAssertEqual(claude.requestedDocuments.count, 1)
    }

    func testCancelledSummaryErrorDoesNotPublishErrorMessage() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()
        try repository.save(document)
        try repository.saveSummary("# 舊摘要", meetingId: document.meeting.id)
        let generator = SuspendedSummaryGenerator()
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: document.meeting.id)
        let task = Task {
            await viewModel.generateSummary(using: .codex)
        }
        await generator.waitUntilRequested()
        task.cancel()
        generator.resume(throwing: TestSummaryError.failed)
        await waitForSummaryTask(task)

        XCTAssertEqual(try repository.loadSummary(meetingId: document.meeting.id), "# 舊摘要")
        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testMeetingRoundTripRejectsStaleSummaryError() async throws {
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
        viewModel.load(meetingId: meetingA.meeting.id)
        generator.resume(throwing: TestSummaryError.failed)
        await waitForSummaryTask(task)

        XCTAssertEqual(viewModel.document?.meeting.id, meetingA.meeting.id)
        XCTAssertNil(viewModel.errorMessage)
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

    func testLoadCancelsSummaryWithoutSavingStaleOutput() async throws {
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
        await waitForSummaryTask(task)

        XCTAssertNil(try repository.loadSummary(meetingId: meetingA.meeting.id))
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
    private let requested = XCTestExpectation(description: "summary requested")
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
            lock.unlock()
            requested.fulfill()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
                resume(throwing: SummaryTestTimeout.expired)
            }
        }
    }

    func waitUntilRequested() async {
        let result = await XCTWaiter.fulfillment(of: [requested], timeout: 2)
        XCTAssertEqual(result, .completed)
    }

    func resume(with summary: String) {
        lock.lock()
        let summaryContinuation = summaryContinuation
        self.summaryContinuation = nil
        lock.unlock()

        summaryContinuation?.resume(returning: summary)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let summaryContinuation = summaryContinuation
        self.summaryContinuation = nil
        lock.unlock()

        summaryContinuation?.resume(throwing: error)
    }
}

// The generation task has completed before the gate opens. Tests can
// invalidate it synchronously, without racing a separately scheduled MainActor job.
private final class SummaryResultPublicationGate: @unchecked Sendable {
    private let completed = XCTestExpectation(description: "provider result completed")
    let allowPublication = XCTestExpectation(description: "allow completed result publication")

    func value(of task: Task<String, Error>) async throws -> String {
        let summary = try await task.value
        completed.fulfill()
        let result = await XCTWaiter.fulfillment(of: [allowPublication], timeout: 2)
        guard result == .completed else {
            XCTFail("Publication gate timed out")
            throw SummaryTestTimeout.expired
        }
        return summary
    }

    func waitUntilCompleted() async {
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(result, .completed)
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
