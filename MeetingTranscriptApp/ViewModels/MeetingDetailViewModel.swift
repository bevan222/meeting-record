import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    @Published var document: TranscriptDocument?
    @Published var errorMessage: String?
    @Published var summaryMarkdown: String?
    @Published private(set) var activeSummaryProvider: SummaryProvider?

    private let repository: FileMeetingRepository
    private let markdownExporter: MarkdownTranscriptExporter
    private let codexSummaryGenerator: any SummaryGenerating
    private let claudeSummaryGenerator: any SummaryGenerating
    private let summaryResult: @Sendable (Task<String, Error>) async throws -> String
    private var summaryTask: Task<String, Error>?
    private var activeSummaryRequestID: UUID?
    private var activeSummaryExecutionID: UUID?

    init(
        repository: FileMeetingRepository,
        markdownExporter: MarkdownTranscriptExporter,
        codexSummaryGenerator: any SummaryGenerating,
        claudeSummaryGenerator: any SummaryGenerating,
        summaryResult: @escaping @Sendable (Task<String, Error>) async throws -> String = { try await $0.value }
    ) {
        self.repository = repository
        self.markdownExporter = markdownExporter
        self.codexSummaryGenerator = codexSummaryGenerator
        self.claudeSummaryGenerator = claudeSummaryGenerator
        self.summaryResult = summaryResult
    }

    convenience init(
        repository: FileMeetingRepository,
        markdownExporter: MarkdownTranscriptExporter,
        summaryGenerator: any SummaryGenerating
    ) {
        self.init(
            repository: repository,
            markdownExporter: markdownExporter,
            codexSummaryGenerator: summaryGenerator,
            claudeSummaryGenerator: summaryGenerator
        )
    }

    var canGenerateSummary: Bool {
        guard let document else { return false }
        return !document.segments.isEmpty && activeSummaryProvider == nil
    }

    var isGeneratingSummary: Bool {
        activeSummaryProvider != nil
    }

    func load(meetingId: String?) {
        cancelActiveSummary()

        guard let meetingId else {
            document = nil
            errorMessage = nil
            summaryMarkdown = nil
            return
        }

        let loadedDocument: TranscriptDocument
        do {
            loadedDocument = try repository.loadTranscript(meetingId: meetingId)
            document = loadedDocument
        } catch {
            document = nil
            summaryMarkdown = nil
            errorMessage = error.localizedDescription
            return
        }

        do {
            summaryMarkdown = try repository.loadSummary(meetingId: loadedDocument.meeting.id)
            errorMessage = nil
        } catch {
            summaryMarkdown = nil
            errorMessage = error.localizedDescription
        }
    }

    func updateSegmentText(segmentId: String, text: String) {
        guard var document else { return }

        document.segments = document.segments.map { segment in
            guard segment.id == segmentId else { return segment }

            var copy = segment
            copy.text = text
            return copy
        }

        save(document)
    }

    @discardableResult
    func updateMeetingTitle(_ title: String) -> String? {
        guard var document else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.meeting.title = trimmedTitle.isEmpty ? "Untitled Meeting" : trimmedTitle

        return save(document) ? document.meeting.title : nil
    }

    func renameSpeaker(speakerId: String, name: String) {
        guard var document else { return }

        document.speakers = document.speakers.map { speaker in
            guard speaker.id == speakerId else { return speaker }

            var copy = speaker
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.name = trimmedName.isEmpty ? nil : trimmedName
            return copy
        }

        save(document)
    }

    func exportMarkdown() {
        guard let document else { return }

        do {
            let markdown = markdownExporter.export(document)
            try repository.saveMarkdown(markdown, meetingId: document.meeting.id)
            try repository.exportMarkdown(markdown, meeting: document.meeting)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportJSON() {
        guard let document else { return }

        guard save(document) else { return }

        do {
            try repository.exportJSON(document)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func meetingFolderURL() -> URL? {
        guard let document else { return nil }

        do {
            let url = try repository.meetingDirectory(for: document.meeting.id)
            errorMessage = nil
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func generateSummary() async {
        await generateSummary(using: .codex)
    }

    func generateSummary(using provider: SummaryProvider) async {
        guard activeSummaryProvider == nil else { return }
        guard let document else { return }
        guard !document.segments.isEmpty else {
            errorMessage = "No transcript segments are available for summary."
            return
        }

        let originalMeetingId = document.meeting.id
        guard save(document) else { return }

        let directory: URL
        do {
            directory = try repository.meetingDirectory(for: originalMeetingId)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let generator: any SummaryGenerating
        switch provider {
        case .codex:
            generator = codexSummaryGenerator
        case .claude:
            generator = claudeSummaryGenerator
        }

        let requestID = UUID()
        activeSummaryRequestID = requestID
        activeSummaryExecutionID = requestID
        activeSummaryProvider = provider
        let task = Task {
            let summary = try await generator.generateSummary(for: document, meetingDirectory: directory)
            try Task.checkCancellation()
            return summary
        }
        summaryTask = task
        defer {
            if activeSummaryExecutionID == requestID {
                summaryTask = nil
                activeSummaryRequestID = nil
                activeSummaryExecutionID = nil
                activeSummaryProvider = nil
            }
        }

        do {
            let summary = try await withTaskCancellationHandler {
                try await summaryResult(task)
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard canPublishSummary(
                requestID: requestID,
                meetingID: originalMeetingId,
                task: task
            ) else { return }

            try repository.saveSummary(summary, meetingId: originalMeetingId)
            guard canPublishSummary(
                requestID: requestID,
                meetingID: originalMeetingId,
                task: task
            ) else { return }

            let summaryMarkdown = try repository.loadSummary(meetingId: originalMeetingId)
            guard canPublishSummary(
                requestID: requestID,
                meetingID: originalMeetingId,
                task: task
            ) else { return }

            self.summaryMarkdown = summaryMarkdown
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard canPublishSummary(
                requestID: requestID,
                meetingID: originalMeetingId,
                task: task
            ) else { return }

            errorMessage = error.localizedDescription
        }
    }

    private func canPublishSummary(
        requestID: UUID,
        meetingID: String,
        task: Task<String, Error>
    ) -> Bool {
        activeSummaryRequestID == requestID
            && document?.meeting.id == meetingID
            && !Task.isCancelled
            && !task.isCancelled
    }

    private func cancelActiveSummary() {
        activeSummaryRequestID = nil
        summaryTask?.cancel()
    }

    @discardableResult
    private func save(_ document: TranscriptDocument) -> Bool {
        do {
            try repository.save(document)
            if self.document != document {
                cancelActiveSummary()
            }
            self.document = document
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
