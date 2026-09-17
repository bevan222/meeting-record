import AppKit
import XCTest
@testable import MeetingTranscriptApp

@MainActor
final class RecordingFloatingPanelControllerTests: XCTestCase {
    func testShowsOnlyForMinimizedActiveRecordingWithSnapshot() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})

        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 61
        )

        XCTAssertEqual(presenter.shownSnapshots, [FloatingRecorderSnapshot(title: "Weekly review", elapsedSeconds: 61)])
    }

    func testDoesNotShowForActiveRecordingWhenMainWindowIsNotMinimized() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: false)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})

        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 61
        )

        XCTAssertEqual(presenter.shownSnapshots, [])
    }

    func testHidesForEachInvalidRecordingCondition() {
        let invalidStates: [(MacAudioRecorder.State, String?)] = [
            (.stopping, "Weekly review"),
            (.failed("Recorder failed."), "Weekly review"),
            (.recording(startedAt: Date()), nil)
        ]

        for (state, title) in invalidStates {
            let presenter = FakeFloatingRecorderPresenter()
            let window = FakeMainWindow(isMiniaturized: true)
            let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
            controller.attach(to: window)
            controller.update(
                recorderState: .recording(startedAt: Date()),
                activeRecordingTitle: "Weekly review",
                elapsedSeconds: 61
            )

            controller.update(recorderState: state, activeRecordingTitle: title, elapsedSeconds: 62)

            XCTAssertEqual(presenter.hideCount, 1)
            XCTAssertEqual(presenter.shownSnapshots.count, 1)
        }
    }

    func testUpdatesVisiblePanelForSubsequentTitleAndElapsedChanges() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Draft title",
            elapsedSeconds: 1
        )

        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Renamed meeting",
            elapsedSeconds: 65
        )

        XCTAssertEqual(presenter.shownSnapshots.count, 1)
        XCTAssertEqual(
            presenter.updatedSnapshots,
            [FloatingRecorderSnapshot(title: "Renamed meeting", elapsedSeconds: 65)]
        )
    }

    func testDeminiaturizeHidesVisiblePanel() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )

        window.isMiniaturized = false
        controller.mainWindowDidDeminiaturize()

        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testDetachHidesVisiblePanel() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )

        controller.detach()

        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testRestoreDeminiaturizesBringsForwardAndActivatesAttachedMainWindow() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
        controller.attach(to: window)

        controller.restoreMainWindow()

        XCTAssertEqual(window.deminiaturizeCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(window.activateApplicationCount, 1)
    }

    func testStopInvokesClosureOnlyOnceBeforeRecorderStateChanges() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        var stopCount = 0
        let controller = RecordingFloatingPanelController(presenter: presenter) {
            stopCount += 1
        }
        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )

        controller.stopRecording()
        controller.stopRecording()

        XCTAssertEqual(stopCount, 1)
    }
}

@MainActor
private final class FakeFloatingRecorderPresenter: FloatingRecorderPanelPresenting {
    private(set) var shownSnapshots: [FloatingRecorderSnapshot] = []
    private(set) var updatedSnapshots: [FloatingRecorderSnapshot] = []
    private(set) var hideCount = 0

    func show(snapshot: FloatingRecorderSnapshot) {
        shownSnapshots.append(snapshot)
    }

    func update(snapshot: FloatingRecorderSnapshot) {
        updatedSnapshots.append(snapshot)
    }

    func hide() {
        hideCount += 1
    }
}

@MainActor
private final class FakeMainWindow: MainWindowControlling {
    var isMiniaturized: Bool
    var notificationWindow: NSWindow? { nil }
    private(set) var deminiaturizeCount = 0
    private(set) var makeKeyAndOrderFrontCount = 0
    private(set) var activateApplicationCount = 0

    init(isMiniaturized: Bool) {
        self.isMiniaturized = isMiniaturized
    }

    func deminiaturize() {
        deminiaturizeCount += 1
        isMiniaturized = false
    }

    func makeKeyAndOrderFront() {
        makeKeyAndOrderFrontCount += 1
    }

    func activateApplication() {
        activateApplicationCount += 1
    }
}
