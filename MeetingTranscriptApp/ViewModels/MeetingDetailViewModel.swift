import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    @Published var document: TranscriptDocument?
    @Published var errorMessage: String?

    private let repository: FileMeetingRepository
    private let markdownExporter: MarkdownTranscriptExporter

    init(repository: FileMeetingRepository, markdownExporter: MarkdownTranscriptExporter) {
        self.repository = repository
        self.markdownExporter = markdownExporter
    }

    func load(meetingId: String?) {
        guard let meetingId else {
            document = nil
            errorMessage = nil
            return
        }

        do {
            document = try repository.loadTranscript(meetingId: meetingId)
            errorMessage = nil
        } catch {
            document = nil
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

    private func save(_ document: TranscriptDocument) {
        do {
            try repository.save(document)
            self.document = document
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
