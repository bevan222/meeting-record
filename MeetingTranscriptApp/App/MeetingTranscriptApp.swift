import SwiftUI

@main
struct MeetingTranscriptApplication: App {
    @StateObject private var container: AppContainer
    @StateObject private var floatingPanelController: RecordingFloatingPanelController

    init() {
        let container = AppContainer()
        _container = StateObject(wrappedValue: container)
        _floatingPanelController = StateObject(
            wrappedValue: RecordingFloatingPanelController {
                container.meetingListViewModel.stopRecording(container: container)
            }
        )
    }

    var body: some Scene {
        Window("Meet Note", id: "main") {
            FloatingRecorderRootView(
                listViewModel: container.meetingListViewModel,
                floatingPanelController: floatingPanelController
            )
                .environmentObject(container)
        }
        .windowStyle(.titleBar)
    }
}
