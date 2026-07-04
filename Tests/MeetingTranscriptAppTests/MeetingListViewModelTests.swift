import Combine
import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

@MainActor
final class MeetingListViewModelTests: XCTestCase {
    func testActiveRecordingContextIsPublishedForRecordingAvailabilityRefresh() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let viewModel = MeetingListViewModel(repository: repository)

        let publishedContextStorage = Mirror(reflecting: viewModel).children.first { child in
            child.label == "_activeRecordingContext"
        }

        XCTAssertNotNil(
            publishedContextStorage,
            "activeRecordingContext must be @Published so canStartRecording refreshes after it changes."
        )
    }

    func testReplacementRecorderStateChangePublishesViewModelChange() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let viewModel = MeetingListViewModel(repository: repository)
        let recorder = FailingStopRecorder()
        viewModel.recorder = recorder

        let viewModelChanged = expectation(description: "View model publishes when recorder changes")
        var cancellable: AnyCancellable?
        cancellable = viewModel.objectWillChange.sink {
            viewModelChanged.fulfill()
        }

        recorder.state = .failed("Delegate failed.")

        await fulfillment(of: [viewModelChanged], timeout: 1)
        _ = cancellable
    }

    func testStopFailurePersistsFailedDocumentAndAllowsNewRecording() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(repository: repository)
        let recorder = FailingStopRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        viewModel.stopRecording(container: container)
        let failedDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .failed
        }

        XCTAssertEqual(failedDocument.meeting.id, recordingDocument.meeting.id)
        XCTAssertEqual(failedDocument.meeting.title, recordingDocument.meeting.title)
        XCTAssertEqual(failedDocument.meeting.recordedAt, recordingDocument.meeting.recordedAt)
        XCTAssertEqual(failedDocument.meeting.language, recordingDocument.meeting.language)
        XCTAssertEqual(failedDocument.meeting.sourceAudio, recordingDocument.meeting.sourceAudio)
        XCTAssertEqual(failedDocument.meeting.durationSeconds, 12)
        XCTAssertEqual(failedDocument.segments, [])
        XCTAssertEqual(viewModel.errorMessage, "Stop failed.")
        XCTAssertTrue(viewModel.canStartRecording)
    }

    func testStopSuccessPersistsInjectedWorkflowTranscript() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(repository: repository, workflow: SucceedingWorkflow())
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        viewModel.stopRecording(container: container)
        let completedDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }

        XCTAssertEqual(completedDocument.segments.map(\.text), ["真實 WhisperKit 逐字稿"])
        XCTAssertEqual(completedDocument.segments[0].speakerId, "speaker_1")
        XCTAssertEqual(container.meetingDetailViewModel.document?.segments.map(\.text), ["真實 WhisperKit 逐字稿"])
    }

    func testStopPersistsTranscribingStatusWhileWorkflowRuns() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let workflow = BlockingWorkflow()
        let container = AppContainer(repository: repository, workflow: workflow)
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        viewModel.stopRecording(container: container)
        let transcribingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .transcribing
        }

        XCTAssertEqual(transcribingDocument.speakers, [])
        XCTAssertEqual(transcribingDocument.segments, [])
        XCTAssertFalse(viewModel.canStartRecording)

        workflow.complete()
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testStopPersistsDiarizingStatusWhileWorkflowRuns() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let workflow = DiarizingBlockingWorkflow()
        let container = AppContainer(repository: repository, workflow: workflow)
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        viewModel.stopRecording(container: container)
        let diarizingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .diarizing
        }

        XCTAssertEqual(diarizingDocument.speakers, [])
        XCTAssertEqual(diarizingDocument.segments, [])
        XCTAssertFalse(viewModel.canStartRecording)

        workflow.complete()
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testStopWorkflowFailurePersistsFailedDocumentAndAllowsNewRecording() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(repository: repository, workflow: FailingWorkflow())
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        viewModel.stopRecording(container: container)
        let failedDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .failed
        }

        XCTAssertEqual(failedDocument.segments, [])
        XCTAssertEqual(viewModel.errorMessage, "Workflow failed.")
        XCTAssertTrue(viewModel.canStartRecording)
    }

    func testLivePreviewTickUpdatesUiOnlyPreviewSegmentsWithoutSavingTranscript() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let previewTranscriber = SucceedingLivePreviewTranscriber()
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: previewTranscriber
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        await viewModel.runLivePreviewTick(container: container)

        XCTAssertEqual(viewModel.livePreviewSegments.map(\.text), ["暫定逐字稿"])
        XCTAssertNil(viewModel.livePreviewWarning)

        let savedDocument = try repository.loadTranscript(meetingId: recordingDocument.meeting.id)
        XCTAssertEqual(savedDocument.segments, [])
        XCTAssertEqual(previewTranscriber.requestedAudioURLs.map(\.lastPathComponent), ["audio.m4a"])

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testStartRecordingBeginsLivePreviewLoop() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let previewTranscriber = SucceedingLivePreviewTranscriber()
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: previewTranscriber
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        XCTAssertTrue(viewModel.isLivePreviewLoopActive)

        viewModel.stopRecording(container: container)
        try await waitForLivePreviewLoopInactive(viewModel)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testStopRecordingClearsLivePreviewBeforeFinalProcessing() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: SucceedingLivePreviewTranscriber()
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }
        await viewModel.runLivePreviewTick(container: container)
        XCTAssertFalse(viewModel.livePreviewSegments.isEmpty)

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }

        XCTAssertEqual(viewModel.livePreviewSegments, [])
        XCTAssertNil(viewModel.livePreviewWarning)
        XCTAssertFalse(viewModel.isLivePreviewLoopActive)
    }

    func testLivePreviewFailureSetsWarningWithoutFailingMeeting() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: FailingLivePreviewTranscriber()
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        await viewModel.runLivePreviewTick(container: container)

        XCTAssertEqual(viewModel.livePreviewSegments, [])
        XCTAssertEqual(viewModel.livePreviewWarning, "暫定逐字稿更新失敗，停止錄音後仍會產生正式逐字稿。")
        XCTAssertEqual(try repository.loadTranscript(meetingId: recordingDocument.meeting.id).meeting.status, .recording)

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testLivePreviewTickSkipsWhenRecorderIsNoLongerRecording() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let previewTranscriber = SucceedingLivePreviewTranscriber()
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: previewTranscriber
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        recorder.state = .stopping
        await viewModel.runLivePreviewTick(container: container)

        XCTAssertEqual(previewTranscriber.requestedAudioURLs, [])
        XCTAssertEqual(viewModel.livePreviewSegments, [])

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testLivePreviewTickFinishingAfterRecorderStopsDoesNotPublishSegments() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let previewTranscriber = BlockingLivePreviewTranscriber()
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: previewTranscriber
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        let tick = Task { await viewModel.runLivePreviewTick(container: container) }
        try await waitForPreviewStart(previewTranscriber)
        recorder.state = .stopping

        previewTranscriber.complete()
        await tick.value

        XCTAssertEqual(viewModel.livePreviewSegments, [])

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testLivePreviewClearsWhenStoppingBeforeWorkflowCompletes() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let workflow = BlockingWorkflow()
        let container = AppContainer(
            repository: repository,
            workflow: workflow,
            livePreviewTranscriber: SucceedingLivePreviewTranscriber()
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        await viewModel.runLivePreviewTick(container: container)
        XCTAssertEqual(viewModel.livePreviewSegments.map(\.text), ["暫定逐字稿"])

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .transcribing
        }

        XCTAssertEqual(viewModel.livePreviewSegments, [])
        XCTAssertNil(viewModel.livePreviewWarning)
        XCTAssertFalse(viewModel.isLivePreviewUpdating)

        workflow.complete()
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testLivePreviewSkipsOverlappingTick() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let previewTranscriber = BlockingLivePreviewTranscriber()
        let container = AppContainer(
            repository: repository,
            workflow: SucceedingWorkflow(),
            livePreviewTranscriber: previewTranscriber
        )
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let recordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }

        let firstTick = Task { await viewModel.runLivePreviewTick(container: container) }
        try await waitForPreviewStart(previewTranscriber)
        await viewModel.runLivePreviewTick(container: container)

        XCTAssertEqual(previewTranscriber.startedCount, 1)

        previewTranscriber.complete()
        await firstTick.value
        XCTAssertEqual(viewModel.livePreviewSegments.map(\.text), ["解除阻塞後的暫定逐字稿"])

        viewModel.stopRecording(container: container)
        _ = try await waitForTranscript(in: repository) { document in
            document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }
    }

    func testEachSuccessfulRecordingUsesIndependentMeetingFolderAudio() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(repository: repository, workflow: SucceedingWorkflow())
        let recorder = SuccessfulRecorder()
        let viewModel = container.meetingListViewModel
        viewModel.recorder = recorder

        viewModel.startRecording(container: container)
        let firstRecordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording
        }
        viewModel.stopRecording(container: container)
        let firstCompletedDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == firstRecordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }

        viewModel.startRecording(container: container)
        let secondRecordingDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.status == .recording && document.meeting.id != firstCompletedDocument.meeting.id
        }
        viewModel.stopRecording(container: container)
        let secondCompletedDocument = try await waitForTranscript(in: repository) { document in
            document.meeting.id == secondRecordingDocument.meeting.id && document.meeting.status == .speakerAttributed
        }

        XCTAssertNotEqual(firstCompletedDocument.meeting.id, secondCompletedDocument.meeting.id)
        for document in [firstCompletedDocument, secondCompletedDocument] {
            let directory = try repository.meetingDirectory(for: document.meeting.id)
            XCTAssertEqual(document.meeting.sourceAudio, "audio.m4a")
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio.m4a").path))
        }
    }

    func testStartFailureDoesNotPersistPlaceholderTranscript() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let container = AppContainer(repository: repository)
        let viewModel = container.meetingListViewModel
        viewModel.recorder = FailingStartRecorder()

        viewModel.startRecording(container: container)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(try repository.listMeetings(), [])
        XCTAssertEqual(viewModel.errorMessage, "Recording could not be started.")
        XCTAssertTrue(viewModel.canStartRecording)
    }

    private static func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitForTranscript(
        in repository: FileMeetingRepository,
        matching predicate: (TranscriptDocument) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> TranscriptDocument {
        for _ in 0..<50 {
            for metadata in try repository.listMeetings() {
                let document = try repository.loadTranscript(meetingId: metadata.id)
                if predicate(document) {
                    return document
                }
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for transcript", file: file, line: line)
        throw WaitError.timedOut
    }

    private func waitForPreviewStart(
        _ transcriber: BlockingLivePreviewTranscriber,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<50 {
            if transcriber.startedCount == 1 {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for live preview tick to start", file: file, line: line)
        throw WaitError.timedOut
    }

    private func waitForLivePreviewLoopInactive(
        _ viewModel: MeetingListViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<50 {
            if !viewModel.isLivePreviewLoopActive {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for live preview loop to stop", file: file, line: line)
        throw WaitError.timedOut
    }
}

@MainActor
private final class FailingStopRecorder: MacAudioRecorder {
    override func requestPermission() async -> Bool {
        true
    }

    override func startRecording(to url: URL, requestPermissionIfNeeded: Bool) async {
        elapsedSeconds = 0
        state = .recording(startedAt: Date())
    }

    override func stopRecording() async -> URL? {
        elapsedSeconds = 12
        state = .failed("Stop failed.")
        return nil
    }
}

@MainActor
private final class SuccessfulRecorder: MacAudioRecorder {
    override func requestPermission() async -> Bool {
        true
    }

    override func startRecording(to url: URL, requestPermissionIfNeeded: Bool) async {
        try? Data("audio".utf8).write(to: url)
        elapsedSeconds = 0
        state = .recording(startedAt: Date())
    }

    override func stopRecording() async -> URL? {
        elapsedSeconds = 3
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try? Data("audio".utf8).write(to: temporaryURL)
        state = .saved(temporaryURL)
        return temporaryURL
    }
}

private struct SucceedingWorkflow: TranscriptBuilding {
    func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument {
        TranscriptDocument(
            meeting: Meeting(
                id: meeting.id,
                title: meeting.title,
                recordedAt: meeting.recordedAt,
                durationSeconds: meeting.durationSeconds,
                language: meeting.language,
                sourceAudio: audioURL.lastPathComponent,
                status: .speakerAttributed
            ),
            speakers: [Speaker(id: "speaker_1", label: "Speaker 1", name: nil)],
            segments: [TranscriptSegment(id: "seg_0001", start: 0, end: 3, speakerId: "speaker_1", text: "真實 WhisperKit 逐字稿", confidence: nil)]
        )
    }
}

private final class BlockingWorkflow: TranscriptBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var isComplete = false

    func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument {
        let deadline = Date().addingTimeInterval(5)
        while !completed {
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        return TranscriptDocument(
            meeting: Meeting(
                id: meeting.id,
                title: meeting.title,
                recordedAt: meeting.recordedAt,
                durationSeconds: meeting.durationSeconds,
                language: meeting.language,
                sourceAudio: audioURL.lastPathComponent,
                status: .speakerAttributed
            ),
            speakers: [Speaker(id: "speaker_1", label: "Speaker 1", name: nil)],
            segments: [TranscriptSegment(id: "seg_0001", start: 0, end: 3, speakerId: "speaker_1", text: "完成逐字稿", confidence: nil)]
        )
    }

    func complete() {
        lock.lock()
        isComplete = true
        lock.unlock()
    }

    private var completed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isComplete
    }

    private struct Timeout: Error {}
}

private final class DiarizingBlockingWorkflow: TranscriptBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var isComplete = false

    func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument {
        try await buildTranscript(for: meeting, audioURL: audioURL, onStatusChange: nil)
    }

    func buildTranscript(
        for meeting: Meeting,
        audioURL: URL,
        onStatusChange: (@MainActor @Sendable (MeetingProcessingState) async -> Void)?
    ) async throws -> TranscriptDocument {
        await onStatusChange?(.diarizing)

        let deadline = Date().addingTimeInterval(5)
        while !completed {
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        return TranscriptDocument(
            meeting: Meeting(
                id: meeting.id,
                title: meeting.title,
                recordedAt: meeting.recordedAt,
                durationSeconds: meeting.durationSeconds,
                language: meeting.language,
                sourceAudio: audioURL.lastPathComponent,
                status: .speakerAttributed
            ),
            speakers: [Speaker(id: "speaker_1", label: "Speaker 1", name: nil)],
            segments: [TranscriptSegment(id: "seg_0001", start: 0, end: 3, speakerId: "speaker_1", text: "完成逐字稿", confidence: nil)]
        )
    }

    func complete() {
        lock.lock()
        isComplete = true
        lock.unlock()
    }

    private var completed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isComplete
    }

    private struct Timeout: Error {}
}

private struct FailingWorkflow: TranscriptBuilding {
    func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument {
        throw Failure()
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Workflow failed."
        }
    }
}

private final class SucceedingLivePreviewTranscriber: LivePreviewTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var audioURLs: [URL] = []

    var requestedAudioURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return audioURLs
    }

    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        lock.withLock {
            audioURLs.append(audioURL)
        }

        return [TranscriptSegment(id: "preview_0001", start: 0, end: 3, speakerId: nil, text: "暫定逐字稿", confidence: nil)]
    }
}

private struct FailingLivePreviewTranscriber: LivePreviewTranscribing {
    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        throw Failure()
    }

    private struct Failure: Error {}
}

private final class BlockingLivePreviewTranscriber: LivePreviewTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var isComplete = false
    private var count = 0

    var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        lock.withLock {
            count += 1
        }

        while !completed {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        return [TranscriptSegment(id: "preview_0001", start: 0, end: 3, speakerId: nil, text: "解除阻塞後的暫定逐字稿", confidence: nil)]
    }

    func complete() {
        lock.lock()
        isComplete = true
        lock.unlock()
    }

    private var completed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isComplete
    }
}

@MainActor
private final class FailingStartRecorder: MacAudioRecorder {
    override func requestPermission() async -> Bool {
        true
    }

    override func startRecording(to url: URL, requestPermissionIfNeeded: Bool) async {
        state = .failed("Recording could not be started.")
    }
}

private enum WaitError: Error {
    case timedOut
}
