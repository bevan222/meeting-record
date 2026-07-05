import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    @Published var document: TranscriptDocument?
    @Published var errorMessage: String?
    @Published var summaryMarkdown: String?
    @Published var isGeneratingSummary = false

    private let repository: FileMeetingRepository
    private let markdownExporter: MarkdownTranscriptExporter
    private let summaryGenerator: any CodexSummaryGenerating

    init(
        repository: FileMeetingRepository,
        markdownExporter: MarkdownTranscriptExporter,
        summaryGenerator: any CodexSummaryGenerating
    ) {
        self.repository = repository
        self.markdownExporter = markdownExporter
        self.summaryGenerator = summaryGenerator
    }

    var canGenerateSummary: Bool {
        guard let document else { return false }
        return !document.segments.isEmpty && !isGeneratingSummary
    }

    func load(meetingId: String?) {
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
            try repository.saveMarkdown(markdownExporter.export(document), meetingId: document.meeting.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportJSON() {
        guard let document else { return }

        save(document)
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
        guard !isGeneratingSummary else { return }
        guard let document else { return }
        guard !document.segments.isEmpty else {
            errorMessage = "No transcript segments are available for summary."
            return
        }

        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        let originalMeetingId = document.meeting.id
        guard save(document) else { return }

        do {
            let directory = try repository.meetingDirectory(for: originalMeetingId)
            let summary = try await summaryGenerator.generateSummary(for: document, meetingDirectory: directory)
            try repository.saveSummary(summary, meetingId: originalMeetingId)
            guard self.document?.meeting.id == originalMeetingId else { return }

            summaryMarkdown = try repository.loadSummary(meetingId: originalMeetingId)
            errorMessage = nil
        } catch {
            guard self.document?.meeting.id == originalMeetingId else { return }

            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func save(_ document: TranscriptDocument) -> Bool {
        do {
            try repository.save(document)
            self.document = document
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
