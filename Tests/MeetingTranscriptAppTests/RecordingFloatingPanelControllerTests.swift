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

    func testOutgoingRootCannotDetachNewerMainWindowOwner() {
        let presenter = FakeFloatingRecorderPresenter()
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
        let firstWindow = FakeMainWindow(isMiniaturized: true)
        let secondWindow = FakeMainWindow(isMiniaturized: true)

        let firstAttachment = controller.attach(to: firstWindow)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )

        _ = controller.attach(to: secondWindow)
        controller.detach(attachment: firstAttachment)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 2
        )

        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(presenter.shownSnapshots.count, 2)
        XCTAssertEqual(presenter.updatedSnapshots.last?.elapsedSeconds, 2)
    }

    func testOutgoingSameWindowOwnerCannotDetachNewerAttachment() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})

        let firstAttachment = controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )

        let secondAttachment = controller.attach(to: window)
        controller.detach(attachment: firstAttachment)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 2
        )

        XCTAssertNotEqual(firstAttachment, secondAttachment)
        XCTAssertEqual(presenter.hideCount, 0)
        XCTAssertEqual(presenter.shownSnapshots.count, 1)
        XCTAssertEqual(presenter.updatedSnapshots.last?.elapsedSeconds, 2)
    }

    func testQueuedCloseFromPreviousAttachmentDoesNotDetachNewerWindow() {
        let notifications = FakeMainWindowNotificationObserver()
        let presenter = FakeFloatingRecorderPresenter()
        let controller = RecordingFloatingPanelController(
            presenter: presenter,
            notificationObserver: notifications,
            onStop: {}
        )
        let firstWindow = FakeMainWindow(isMiniaturized: true)
        let secondWindow = FakeMainWindow(isMiniaturized: true)

        _ = controller.attach(to: firstWindow)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )
        let firstNotificationObject = try! XCTUnwrap(firstWindow.notificationObject)
        let queuedClose = try! XCTUnwrap(
            notifications.handler(for: NSWindow.willCloseNotification, object: firstNotificationObject)
        )

        _ = controller.attach(to: secondWindow)
        queuedClose()
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 2
        )

        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(presenter.shownSnapshots.count, 2)
        XCTAssertEqual(presenter.updatedSnapshots.last?.elapsedSeconds, 2)
    }

    func testRestoreDeminiaturizesBringsForwardAndActivatesAttachedMainWindow() {
        let presenter = FakeFloatingRecorderPresenter()
        let window = FakeMainWindow(isMiniaturized: true)
        let controller = RecordingFloatingPanelController(presenter: presenter, onStop: {})
        controller.attach(to: window)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Weekly review",
            elapsedSeconds: 1
        )

        controller.restoreMainWindow()

        XCTAssertEqual(window.deminiaturizeCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCount, 1)
        XCTAssertEqual(window.activateApplicationCount, 1)
        XCTAssertEqual(presenter.hideCount, 1)
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
        XCTAssertEqual(presenter.hideCount, 1)
        controller.stopRecording()

        controller.update(recorderState: .stopping, activeRecordingTitle: "Weekly review", elapsedSeconds: 2)
        controller.update(
            recorderState: .recording(startedAt: Date()),
            activeRecordingTitle: "Follow-up review",
            elapsedSeconds: 3
        )

        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(
            presenter.shownSnapshots,
            [
                FloatingRecorderSnapshot(title: "Weekly review", elapsedSeconds: 1),
                FloatingRecorderSnapshot(title: "Follow-up review", elapsedSeconds: 3)
            ]
        )
    }

    func testFixedPanelGeometryDoesNotChangeForTitleOrElapsedUpdates() {
        let panel = RecordingFloatingPanel()
        let expectedSize = NSSize(width: 320, height: 88)
        let snapshots = [
            FloatingRecorderSnapshot(title: "", elapsedSeconds: 0),
            FloatingRecorderSnapshot(title: "Short", elapsedSeconds: 65),
            FloatingRecorderSnapshot(title: String(repeating: "Long meeting title ", count: 20), elapsedSeconds: 36_599)
        ]

        for snapshot in snapshots {
            panel.update(snapshot: snapshot)

            XCTAssertEqual(panel.contentMinSize, expectedSize)
            XCTAssertEqual(panel.contentMaxSize, expectedSize)
            XCTAssertEqual(panel.fixedContentSize, expectedSize)
            XCTAssertEqual(panel.hostingViewFrame.size, expectedSize)
            XCTAssertEqual(panel.hostingViewFrame, NSRect(origin: .zero, size: expectedSize))
            XCTAssertEqual(panel.contentView?.bounds.size, expectedSize)
        }
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
    private let notificationMarker = NSObject()
    var notificationObject: AnyObject? { notificationMarker }
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

@MainActor
private final class FakeMainWindowNotificationObserver: MainWindowNotificationObserving {
    private final class Token: NSObject {}

    private var handlers: [ObjectIdentifier: (name: Notification.Name, object: AnyObject, handler: @MainActor () -> Void)] = [:]

    func addObserver(
        forName name: Notification.Name,
        object: AnyObject,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        let token = Token()
        handlers[ObjectIdentifier(token)] = (name, object, handler)
        return token
    }

    func removeObserver(_ token: NSObjectProtocol) {
        handlers.removeValue(forKey: ObjectIdentifier(token as AnyObject))
    }

    func handler(for name: Notification.Name, object: AnyObject) -> (@MainActor () -> Void)? {
        handlers.values.first { $0.name == name && $0.object === object }?.handler
    }
}
