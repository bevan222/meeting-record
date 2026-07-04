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
    private var activeRecordingContext: RecordingContext?

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
            guard !recorder.isRecording, activeRecordingContext == nil else { return }

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
                let recordingContext = RecordingContext(
                    meetingId: id,
                    audioURL: audioURL,
                    startedAt: now,
                    title: title,
                    language: "zh-TW"
                )
                let placeholder = TranscriptDocument(
                    meeting: Meeting(
                        id: recordingContext.meetingId,
                        title: recordingContext.title,
                        recordedAt: recordingContext.startedAt,
                        durationSeconds: 0,
                        language: recordingContext.language,
                        sourceAudio: recordingContext.audioURL.lastPathComponent,
                        status: .recording
                    ),
                    speakers: [],
                    segments: []
                )

                try repository.save(placeholder)
                activeRecordingContext = recordingContext
                selectedMeetingId = recordingContext.meetingId
                reload()
                container.meetingDetailViewModel.load(meetingId: recordingContext.meetingId)

                await recorder.startRecording(to: recordingContext.audioURL, requestPermissionIfNeeded: false)
                if case .failed(let message) = recorder.state {
                    activeRecordingContext = nil
                    errorMessage = message
                    var failedDocument = placeholder
                    failedDocument.meeting.status = .failed
                    try? repository.save(failedDocument)
                    reload()
                    container.meetingDetailViewModel.load(meetingId: recordingContext.meetingId)
                }
            } catch {
                activeRecordingContext = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording(container: AppContainer) {
        guard let recordingContext = activeRecordingContext else { return }

        let elapsedSeconds = recorder.elapsedSeconds

        Task { @MainActor in
            guard let audioURL = await recorder.stopRecording() else {
                activeRecordingContext = nil
                errorMessage = recorderFailureMessage
                return
            }

            do {
                var document = try repository.loadTranscript(meetingId: recordingContext.meetingId)
                document.meeting.durationSeconds = max(elapsedSeconds, recorder.elapsedSeconds)
                document.meeting.sourceAudio = audioURL.lastPathComponent
                document.meeting.status = .recorded
                try repository.save(document)
                selectedMeetingId = document.meeting.id
                reload()
                container.meetingDetailViewModel.load(meetingId: document.meeting.id)

                do {
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
            } catch {
                errorMessage = error.localizedDescription
            }

            activeRecordingContext = nil
        }
    }

    private var recorderFailureMessage: String {
        if case .failed(let message) = recorder.state {
            return message
        }
        return "Recording could not be saved."
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

private struct RecordingContext {
    let meetingId: String
    let audioURL: URL
    let startedAt: Date
    let title: String
    let language: String
}
