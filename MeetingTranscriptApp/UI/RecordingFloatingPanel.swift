import AppKit
import Combine
import SwiftUI

struct FloatingRecorderSnapshot: Equatable {
    let title: String
    let elapsedSeconds: TimeInterval
}

@MainActor
protocol FloatingRecorderPanelPresenting: AnyObject {
    func show(snapshot: FloatingRecorderSnapshot)
    func update(snapshot: FloatingRecorderSnapshot)
    func hide()
}

@MainActor
protocol MainWindowControlling: AnyObject {
    var isMiniaturized: Bool { get }
    var notificationObject: AnyObject? { get }

    func deminiaturize()
    func makeKeyAndOrderFront()
    func activateApplication()
}

@MainActor
protocol MainWindowNotificationObserving: AnyObject {
    func addObserver(
        forName name: Notification.Name,
        object: AnyObject,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol
    func removeObserver(_ token: NSObjectProtocol)
}

@MainActor
private final class MainWindowNotificationObserver: MainWindowNotificationObserving {
    func addObserver(
        forName name: Notification.Name,
        object: AnyObject,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }

    func removeObserver(_ token: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(token)
    }
}

struct FloatingRecorderWindowAttachment: Equatable {
    fileprivate let generation: UInt
}

@MainActor
final class RecordingFloatingPanelController: ObservableObject {
    private let presenter: any FloatingRecorderPanelPresenting
    private let notificationObserver: any MainWindowNotificationObserving
    private let onStop: () -> Void
    private var mainWindow: (any MainWindowControlling)?
    private var notificationTokens: [NSObjectProtocol] = []
    private var attachment: FloatingRecorderWindowAttachment?
    private var nextAttachmentGeneration: UInt = 0
    private var recorderState: MacAudioRecorder.State = .idle
    private var snapshot: FloatingRecorderSnapshot?
    private var isPanelVisible = false
    private var isStopRequested = false

    init(
        presenter: any FloatingRecorderPanelPresenting,
        notificationObserver: any MainWindowNotificationObserving = MainWindowNotificationObserver(),
        onStop: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.notificationObserver = notificationObserver
        self.onStop = onStop
    }

    convenience init(onStop: @escaping () -> Void) {
        let panel = RecordingFloatingPanel()
        self.init(presenter: panel, onStop: onStop)
        panel.onStop = { [weak self] in
            self?.stopRecording()
        }
        panel.onRestore = { [weak self] in
            self?.restoreMainWindow()
        }
    }

    isolated deinit {
        removeWindowObservers()
    }

    @discardableResult
    func attach(to mainWindow: any MainWindowControlling) -> FloatingRecorderWindowAttachment {
        if let attachment, isAttached(to: mainWindow) {
            synchronizePanelVisibility()
            return attachment
        }

        detach()
        nextAttachmentGeneration += 1
        let attachment = FloatingRecorderWindowAttachment(generation: nextAttachmentGeneration)
        self.mainWindow = mainWindow
        self.attachment = attachment
        observe(mainWindow, attachment: attachment)
        synchronizePanelVisibility()
        return attachment
    }

    func detach() {
        removeWindowObservers()
        mainWindow = nil
        attachment = nil
        synchronizePanelVisibility()
    }

    func detach(attachment: FloatingRecorderWindowAttachment) {
        guard attachment == self.attachment else { return }
        detach()
    }

    func update(
        recorderState: MacAudioRecorder.State,
        activeRecordingTitle: String?,
        elapsedSeconds: TimeInterval
    ) {
        self.recorderState = recorderState
        snapshot = activeRecordingTitle.map {
            FloatingRecorderSnapshot(title: $0, elapsedSeconds: elapsedSeconds)
        }

        if !isRecording {
            isStopRequested = false
        }

        synchronizePanelVisibility()
    }

    func mainWindowDidMiniaturize() {
        synchronizePanelVisibility()
    }

    func mainWindowDidDeminiaturize() {
        synchronizePanelVisibility()
    }

    func stopRecording() {
        guard isPanelVisible, !isStopRequested else { return }

        isStopRequested = true
        synchronizePanelVisibility()
        onStop()
    }

    func restoreMainWindow() {
        guard let mainWindow else { return }

        mainWindow.deminiaturize()
        mainWindow.makeKeyAndOrderFront()
        mainWindow.activateApplication()
        synchronizePanelVisibility()
    }

    private var isRecording: Bool {
        if case .recording = recorderState {
            return true
        }
        return false
    }

    private var shouldShowPanel: Bool {
        isRecording && !isStopRequested && mainWindow?.isMiniaturized == true && snapshot != nil
    }

    private func synchronizePanelVisibility() {
        guard shouldShowPanel, let snapshot else {
            if isPanelVisible {
                presenter.hide()
                isPanelVisible = false
            }
            return
        }

        if isPanelVisible {
            presenter.update(snapshot: snapshot)
        } else {
            presenter.show(snapshot: snapshot)
            isPanelVisible = true
        }
    }

    private func isAttached(to mainWindow: any MainWindowControlling) -> Bool {
        if let attachedObject = self.mainWindow?.notificationObject,
           let newObject = mainWindow.notificationObject
        {
            return attachedObject === newObject
        }

        guard let attachedWindow = self.mainWindow else { return false }
        return (attachedWindow as AnyObject) === (mainWindow as AnyObject)
    }

    private func observe(
        _ mainWindow: any MainWindowControlling,
        attachment: FloatingRecorderWindowAttachment
    ) {
        guard let notificationObject = mainWindow.notificationObject else { return }

        notificationTokens = [
            notificationObserver.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: notificationObject
            ) { [weak self] in
                self?.handleWindowEvent(.didMiniaturize, attachment: attachment)
            },
            notificationObserver.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: notificationObject
            ) { [weak self] in
                self?.handleWindowEvent(.didDeminiaturize, attachment: attachment)
            },
            notificationObserver.addObserver(
                forName: NSWindow.willCloseNotification,
                object: notificationObject
            ) { [weak self] in
                self?.handleWindowEvent(.willClose, attachment: attachment)
            }
        ]
    }

    private func handleWindowEvent(
        _ event: MainWindowEvent,
        attachment: FloatingRecorderWindowAttachment
    ) {
        guard attachment == self.attachment else { return }

        switch event {
        case .didMiniaturize:
            mainWindowDidMiniaturize()
        case .didDeminiaturize:
            mainWindowDidDeminiaturize()
        case .willClose:
            detach(attachment: attachment)
        }
    }

    private func removeWindowObservers() {
        notificationTokens.forEach(notificationObserver.removeObserver)
        notificationTokens.removeAll()
    }
}

private enum MainWindowEvent {
    case didMiniaturize
    case didDeminiaturize
    case willClose
}

private enum FloatingRecorderPanelLayout {
    static let contentSize = NSSize(width: 320, height: 88)
}

@MainActor
final class RecordingFloatingPanel: NSPanel, FloatingRecorderPanelPresenting {
    var onStop: (() -> Void)?
    var onRestore: (() -> Void)?

    private var hostingView: NSHostingView<FloatingRecorderPanelContent>!

    var fixedContentSize: NSSize {
        FloatingRecorderPanelLayout.contentSize
    }

    var hostingViewFrame: NSRect {
        hostingView.frame
    }

    init() {
        let panelSize = FloatingRecorderPanelLayout.contentSize
        super.init(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        title = "Meet Note"
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        hostingView = NSHostingView(rootView: makeContent(snapshot: nil))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
        contentMinSize = panelSize
        contentMaxSize = panelSize
        setContentSize(panelSize)
    }

    func show(snapshot: FloatingRecorderSnapshot) {
        render(snapshot: snapshot)
        orderFrontRegardless()
    }

    func update(snapshot: FloatingRecorderSnapshot) {
        render(snapshot: snapshot)
    }

    func hide() {
        orderOut(nil)
    }

    private func render(snapshot: FloatingRecorderSnapshot) {
        hostingView.rootView = makeContent(snapshot: snapshot)
    }

    private func makeContent(snapshot: FloatingRecorderSnapshot?) -> FloatingRecorderPanelContent {
        FloatingRecorderPanelContent(
            snapshot: snapshot,
            onStop: { [weak self] in self?.onStop?() },
            onRestore: { [weak self] in self?.onRestore?() }
        )
    }
}

private struct FloatingRecorderPanelContent: View {
    let snapshot: FloatingRecorderSnapshot?
    let onStop: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(formattedElapsedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .help("Stop recording")

            Button(action: onRestore) {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.plain)
            .help("Return to main window")
        }
        .padding(16)
        .frame(
            width: FloatingRecorderPanelLayout.contentSize.width,
            height: FloatingRecorderPanelLayout.contentSize.height
        )
    }

    private var formattedElapsedTime: String {
        let totalSeconds = max(0, Int((snapshot?.elapsedSeconds ?? 0).rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3_600,
            (totalSeconds % 3_600) / 60,
            totalSeconds % 60
        )
    }
}

@MainActor
private final class AppKitMainWindow: MainWindowControlling {
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
    }

    var isMiniaturized: Bool {
        window?.isMiniaturized ?? false
    }

    var notificationObject: AnyObject? {
        window
    }

    func deminiaturize() {
        window?.deminiaturize(nil)
    }

    func makeKeyAndOrderFront() {
        window?.makeKeyAndOrderFront(nil)
    }

    func activateApplication() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    let floatingPanelController: RecordingFloatingPanelController

    func makeNSView(context: Context) -> WindowAccessView {
        WindowAccessView(floatingPanelController: floatingPanelController)
    }

    func updateNSView(_ nsView: WindowAccessView, context: Context) {
        nsView.reportWindow()
    }
}

struct FloatingRecorderRootView: View {
    @ObservedObject var listViewModel: MeetingListViewModel
    let floatingPanelController: RecordingFloatingPanelController

    var body: some View {
        ContentView()
            .background(
                MainWindowAccessor(floatingPanelController: floatingPanelController)
            )
            .onAppear {
                updateFloatingPanel()
            }
            .onChange(of: listViewModel.activeRecordingTitle) { _, _ in
                updateFloatingPanel()
            }
            .onChange(of: listViewModel.recorder.state) { _, _ in
                updateFloatingPanel()
            }
            .onChange(of: listViewModel.recorder.elapsedSeconds) { _, _ in
                updateFloatingPanel()
            }
    }

    private func updateFloatingPanel() {
        floatingPanelController.update(
            recorderState: listViewModel.recorder.state,
            activeRecordingTitle: listViewModel.activeRecordingTitle,
            elapsedSeconds: listViewModel.recorder.elapsedSeconds
        )
    }
}

final class WindowAccessView: NSView {
    private let floatingPanelController: RecordingFloatingPanelController
    private var attachment: FloatingRecorderWindowAttachment?

    init(floatingPanelController: RecordingFloatingPanelController) {
        self.floatingPanelController = floatingPanelController
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        if let window {
            attachment = floatingPanelController.attach(to: AppKitMainWindow(window: window))
        } else if let attachment {
            floatingPanelController.detach(attachment: attachment)
            self.attachment = nil
        }
    }
}
