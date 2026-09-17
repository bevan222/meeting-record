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
    var notificationWindow: NSWindow? { get }

    func deminiaturize()
    func makeKeyAndOrderFront()
    func activateApplication()
}

@MainActor
final class RecordingFloatingPanelController: ObservableObject {
    private let presenter: any FloatingRecorderPanelPresenting
    private let onStop: () -> Void
    private var mainWindow: (any MainWindowControlling)?
    private var notificationTokens: [NSObjectProtocol] = []
    private var recorderState: MacAudioRecorder.State = .idle
    private var snapshot: FloatingRecorderSnapshot?
    private var isPanelVisible = false
    private var isStopRequested = false

    init(presenter: any FloatingRecorderPanelPresenting, onStop: @escaping () -> Void) {
        self.presenter = presenter
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

    func attach(to mainWindow: any MainWindowControlling) {
        if let attachedWindow = self.mainWindow,
           (attachedWindow as AnyObject) === (mainWindow as AnyObject)
        {
            synchronizePanelVisibility()
            return
        }

        if let attachedWindow = self.mainWindow?.notificationWindow,
           let newWindow = mainWindow.notificationWindow,
           attachedWindow === newWindow
        {
            synchronizePanelVisibility()
            return
        }

        detach()
        self.mainWindow = mainWindow
        observe(mainWindow)
        synchronizePanelVisibility()
    }

    func detach() {
        removeWindowObservers()
        mainWindow = nil
        synchronizePanelVisibility()
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

    private func observe(_ mainWindow: any MainWindowControlling) {
        guard let notificationWindow = mainWindow.notificationWindow else { return }

        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: notificationWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.mainWindowDidMiniaturize()
                }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: notificationWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.mainWindowDidDeminiaturize()
                }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: notificationWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.detach()
                }
            }
        ]
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }
}

@MainActor
private final class RecordingFloatingPanel: NSPanel, FloatingRecorderPanelPresenting {
    var onStop: (() -> Void)?
    var onRestore: (() -> Void)?

    private var hostingView: NSHostingView<FloatingRecorderPanelContent>!

    init() {
        let panelSize = NSSize(width: 320, height: 88)
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
        minSize = panelSize
        maxSize = panelSize
        isMovableByWindowBackground = true

        hostingView = NSHostingView(rootView: makeContent(snapshot: nil))
        contentView = hostingView
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

    var notificationWindow: NSWindow? {
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
    let onWindowChanged: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowAccessView {
        WindowAccessView(onWindowChanged: onWindowChanged)
    }

    func updateNSView(_ nsView: WindowAccessView, context: Context) {
        nsView.onWindowChanged = onWindowChanged
        nsView.reportWindow()
    }
}

struct FloatingRecorderRootView: View {
    @ObservedObject var listViewModel: MeetingListViewModel
    let floatingPanelController: RecordingFloatingPanelController

    var body: some View {
        ContentView()
            .background(
                MainWindowAccessor { window in
                    if let window {
                        floatingPanelController.attach(to: AppKitMainWindow(window: window))
                    } else {
                        floatingPanelController.detach()
                    }
                }
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
    var onWindowChanged: (NSWindow?) -> Void

    init(onWindowChanged: @escaping (NSWindow?) -> Void) {
        self.onWindowChanged = onWindowChanged
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
        onWindowChanged(window)
    }
}
