import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingListViewModel: ObservableObject {
    @Published var meetings: [MeetingMetadata] = []
    @Published var selectedMeetingId: String?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var livePreviewSegments: [TranscriptSegment] = []
    @Published var livePreviewWarning: String?
    @Published var isLivePreviewUpdating = false
    @Published var recorder = MacAudioRecorder() {
        didSet {
            subscribeToRecorderChanges()
        }
    }

    private let repository: FileMeetingRepository
    @Published private var activeRecordingContext: RecordingContext?
    private var recorderChanges: AnyCancellable?
    private var livePreviewTask: Task<Void, Never>?
    private var isLivePreviewTranscribing = false
    private var livePreviewGeneration = 0

    init(repository: FileMeetingRepository) {
        self.repository = repository
        subscribeToRecorderChanges()
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

    var canStartRecording: Bool {
        guard recorderCanAcceptStart else { return false }
        guard activeRecordingContext != nil else { return true }

        if case .failed = recorder.state {
            return true
        }
        return false
    }

    var isLivePreviewLoopActive: Bool {
        livePreviewTask != nil
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

            if activeRecordingContext != nil {
                guard case .failed = recorder.state else { return }
                await markActiveRecordingFailed(container: container, measuredDuration: recorder.elapsedSeconds)
            }

            guard activeRecordingContext == nil else { return }

            errorMessage = nil
            clearLivePreview()
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
                await recorder.startRecording(to: recordingContext.audioURL, requestPermissionIfNeeded: false)
                guard recorder.isRecording else {
                    try? FileManager.default.removeItem(at: meetingDirectory)
                    if case .failed(let message) = recorder.state {
                        errorMessage = message
                    } else {
                        errorMessage = recorderFailureMessage
                    }
                    return
                }

                activeRecordingContext = recordingContext
                try repository.save(recordingPreviewDocument(for: recordingContext))
                selectedMeetingId = recordingContext.meetingId
                reload()
                container.meetingDetailViewModel.load(meetingId: recordingContext.meetingId)
                startLivePreviewLoop(livePreviewTranscriber: container.livePreviewTranscriber)
            } catch {
                if recorder.isRecording {
                    _ = await recorder.stopRecording()
                }
                activeRecordingContext = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func stopRecording(container: AppContainer) {
        guard let recordingContext = activeRecordingContext else { return }

        let elapsedSeconds = recorder.elapsedSeconds

        Task { @MainActor in
            clearLivePreview()

            guard let audioURL = await recorder.stopRecording() else {
                await markActiveRecordingFailed(
                    container: container,
                    measuredDuration: max(elapsedSeconds, recorder.elapsedSeconds),
                    message: recorderFailureMessage
                )
                return
            }

            do {
                let finalizedAudioURL = try finalizeRecordingAudio(from: audioURL, for: recordingContext)
                var document = try repository.loadTranscript(meetingId: recordingContext.meetingId)
                document.meeting.durationSeconds = max(elapsedSeconds, recorder.elapsedSeconds)
                document.meeting.sourceAudio = finalizedAudioURL.lastPathComponent
                document.meeting.status = .recorded
                document.speakers = []
                document.segments = []
                try repository.save(document)
                persist(document, container: container)

                do {
                    document.meeting.status = .transcribing
                    try repository.save(document)
                    persist(document, container: container)

                    let completedDocument = try await container.workflow.buildTranscript(
                        for: document.meeting,
                        audioURL: finalizedAudioURL,
                        onStatusChange: { state in
                            document.meeting.status = state
                            document.speakers = []
                            document.segments = []
                            try? self.repository.save(document)
                            self.persist(document, container: container)
                        }
                    )

                    try repository.save(completedDocument)
                    persist(completedDocument, container: container)
                    errorMessage = nil
                } catch {
                    document.meeting.status = .failed
                    try? repository.save(document)
                    persist(document, container: container)
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            activeRecordingContext = nil
            clearLivePreview()
        }
    }

    func runLivePreviewTick(container: AppContainer) async {
        await runLivePreviewTick(livePreviewTranscriber: container.livePreviewTranscriber)
    }

    private func runLivePreviewTick(livePreviewTranscriber: any LivePreviewTranscribing) async {
        guard let recordingContext = activeRecordingContext else { return }
        guard recorder.isRecording else { return }
        guard !isLivePreviewTranscribing else { return }

        let generation = livePreviewGeneration
        isLivePreviewTranscribing = true
        isLivePreviewUpdating = true
        defer {
            if livePreviewGeneration == generation {
                isLivePreviewTranscribing = false
                isLivePreviewUpdating = false
            }
        }

        do {
            let segments = try await livePreviewTranscriber.transcribePreview(
                audioURL: recordingContext.audioURL,
                language: recordingContext.language
            )

            guard canApplyLivePreviewResult(for: recordingContext, generation: generation) else { return }
            livePreviewSegments = segments
            livePreviewWarning = nil
        } catch {
            guard canApplyLivePreviewResult(for: recordingContext, generation: generation) else { return }
            livePreviewWarning = "暫定逐字稿更新失敗，停止錄音後仍會產生正式逐字稿。"
        }
    }

    private func persist(_ document: TranscriptDocument, container: AppContainer) {
        selectedMeetingId = document.meeting.id
        reload()
        container.meetingDetailViewModel.load(meetingId: document.meeting.id)
    }

    private func finalizeRecordingAudio(from recordedAudioURL: URL, for recordingContext: RecordingContext) throws -> URL {
        let expectedAudioURL = recordingContext.audioURL
        guard recordedAudioURL.standardizedFileURL.path != expectedAudioURL.standardizedFileURL.path else {
            return expectedAudioURL
        }

        if FileManager.default.fileExists(atPath: expectedAudioURL.path) {
            try FileManager.default.removeItem(at: expectedAudioURL)
        }
        try FileManager.default.copyItem(at: recordedAudioURL, to: expectedAudioURL)
        return expectedAudioURL
    }

    private var recorderCanAcceptStart: Bool {
        switch recorder.state {
        case .idle, .permissionDenied, .saved, .failed:
            return true
        case .checkingPermission, .recording, .stopping:
            return false
        }
    }

    private func subscribeToRecorderChanges() {
        recorderChanges = recorder.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    private var recorderFailureMessage: String {
        if case .failed(let message) = recorder.state {
            return message
        }
        return "Recording could not be saved."
    }

    private func recordingPreviewDocument(for recordingContext: RecordingContext) -> TranscriptDocument {
        TranscriptDocument(
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
    }

    private func clearLivePreview() {
        livePreviewGeneration += 1
        livePreviewTask?.cancel()
        livePreviewTask = nil
        isLivePreviewTranscribing = false
        isLivePreviewUpdating = false
        livePreviewSegments = []
        livePreviewWarning = nil
    }

    private func startLivePreviewLoop(livePreviewTranscriber: any LivePreviewTranscribing) {
        livePreviewTask?.cancel()
        livePreviewTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.runLivePreviewTick(livePreviewTranscriber: livePreviewTranscriber)
            }
        }
    }

    private func canApplyLivePreviewResult(for recordingContext: RecordingContext, generation: Int) -> Bool {
        activeRecordingContext?.meetingId == recordingContext.meetingId
            && recorder.isRecording
            && livePreviewGeneration == generation
    }

    private func markActiveRecordingFailed(
        container: AppContainer,
        measuredDuration: TimeInterval?,
        message: String? = nil
    ) async {
        guard let recordingContext = activeRecordingContext else {
            errorMessage = message ?? recorderFailureMessage
            return
        }

        let duration = measuredDuration ?? recorder.elapsedSeconds

        do {
            var document = (try? repository.loadTranscript(meetingId: recordingContext.meetingId)) ?? TranscriptDocument(
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

            document.meeting.durationSeconds = max(0, duration)
            document.meeting.status = .failed
            try repository.save(document)
            selectedMeetingId = document.meeting.id
            reload()
            container.meetingDetailViewModel.load(meetingId: document.meeting.id)
            clearLivePreview()
            activeRecordingContext = nil
            errorMessage = message ?? recorderFailureMessage
        } catch {
            clearLivePreview()
            activeRecordingContext = nil
            errorMessage = error.localizedDescription
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

private struct RecordingContext {
    let meetingId: String
    let audioURL: URL
    let startedAt: Date
    let title: String
    let language: String
}
