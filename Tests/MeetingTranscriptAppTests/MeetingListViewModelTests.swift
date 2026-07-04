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
        XCTAssertFalse(recordingDocument.segments.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Stop failed.")
        XCTAssertTrue(viewModel.canStartRecording)
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
