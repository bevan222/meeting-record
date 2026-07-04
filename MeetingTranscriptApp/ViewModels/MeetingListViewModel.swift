import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingListViewModel: ObservableObject {
    @Published var meetings: [MeetingMetadata] = []
    @Published var selectedMeetingId: String?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var recorder = MacAudioRecorder()

    private let repository: FileMeetingRepository

    init(repository: FileMeetingRepository) {
        self.repository = repository
    }

    var filteredMeetings: [MeetingMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return meetings
        }

        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(query)
        }
    }

    func reload() {
        do {
            meetings = try repository.listMeetings()
            errorMessage = nil

            if let selectedMeetingId, meetings.contains(where: { $0.id == selectedMeetingId }) {
                return
            }
            selectedMeetingId = meetings.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording(container: AppContainer) {
        Task { @MainActor in
            guard !recorder.isRecording else { return }

            errorMessage = nil
            guard await recorder.requestPermission() else {
                errorMessage = "Microphone access was denied."
                return
            }

            let now = Date()
            let title = "Untitled Meeting"

            do {
                let id = try makeUniqueMeetingId(date: now)
                let meetingDirectory = try repository.createMeetingDirectory(meetingId: id)
                let audioURL = meetingDirectory.appendingPathComponent("audio.m4a")
                let placeholder = TranscriptDocument(
                    meeting: Meeting(
                        id: id,
                        title: title,
                        recordedAt: now,
                        durationSeconds: 0,
                        language: "zh-TW",
                        sourceAudio: "audio.m4a",
                        status: .recording
                    ),
                    speakers: [],
                    segments: []
                )

                try repository.save(placeholder)
                selectedMeetingId = id
                reload()
                container.meetingDetailViewModel.load(meetingId: id)

                await recorder.startRecording(to: audioURL, requestPermissionIfNeeded: false)
                if case .failed(let message) = recorder.state {
                    errorMessage = message
                    var failedDocument = placeholder
                    failedDocument.meeting.status = .failed
                    try? repository.save(failedDocument)
                    reload()
                    container.meetingDetailViewModel.load(meetingId: id)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording(container: AppContainer) {
        let elapsedSeconds = recorder.elapsedSeconds
        recorder.stopRecording()

        guard case .saved(let audioURL) = recorder.state else { return }

        Task { @MainActor in
            let meetingId = selectedMeetingId ?? audioURL.deletingLastPathComponent().lastPathComponent

            do {
                var document = try repository.loadTranscript(meetingId: meetingId)
                document.meeting.durationSeconds = max(elapsedSeconds, recorder.elapsedSeconds)
                document.meeting.sourceAudio = audioURL.lastPathComponent
                document.meeting.status = .recorded

                let completedDocument = try await container.workflow.buildTranscript(
                    for: document.meeting,
                    audioURL: audioURL
                )

                try repository.save(completedDocument)
                selectedMeetingId = completedDocument.meeting.id
                reload()
                container.meetingDetailViewModel.load(meetingId: completedDocument.meeting.id)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func makeUniqueMeetingId(date: Date) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let base = formatter.string(from: date) + "-meeting"
        var candidate = base
        var suffix = 2

        while FileManager.default.fileExists(atPath: try repository.meetingDirectory(for: candidate).path) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return candidate
    }
}
