import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ContentBody(
            container: container,
            listViewModel: container.meetingListViewModel,
            detailViewModel: container.meetingDetailViewModel
        )
    }
}

private struct ContentBody: View {
    let container: AppContainer
    @ObservedObject var listViewModel: MeetingListViewModel
    @ObservedObject var detailViewModel: MeetingDetailViewModel

    var body: some View {
        NavigationSplitView {
            MeetingListView(viewModel: listViewModel)
                .frame(minWidth: 260)
        } detail: {
            MeetingDetailView(
                viewModel: detailViewModel,
                recorder: listViewModel.recorder,
                canStartRecording: listViewModel.canStartRecording,
                livePreviewSegments: listViewModel.livePreviewSegments,
                livePreviewWarning: listViewModel.livePreviewWarning,
                isLivePreviewUpdating: listViewModel.isLivePreviewUpdating,
                onRecord: { listViewModel.startRecording(container: container) },
                onStop: { listViewModel.stopRecording(container: container) },
                onMeetingMetadataChanged: { listViewModel.reload() }
            )
        }
        .onAppear {
            listViewModel.reload()
            detailViewModel.load(meetingId: listViewModel.selectedMeetingId)
        }
        .onChange(of: listViewModel.selectedMeetingId) { _, newValue in
            detailViewModel.load(meetingId: newValue)
        }
    }
}
