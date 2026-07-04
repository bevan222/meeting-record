import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ContentBody(
            listViewModel: container.meetingListViewModel,
            detailViewModel: container.meetingDetailViewModel
        )
    }
}

private struct ContentBody: View {
    @ObservedObject var listViewModel: MeetingListViewModel
    @ObservedObject var detailViewModel: MeetingDetailViewModel

    var body: some View {
        NavigationSplitView {
            MeetingListView(viewModel: listViewModel)
                .frame(minWidth: 260)
        } detail: {
            MeetingDetailView(viewModel: detailViewModel, selectedMeetingId: listViewModel.selectedMeetingId)
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
