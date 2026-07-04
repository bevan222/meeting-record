import SwiftUI

struct MeetingListView: View {
    @ObservedObject var viewModel: MeetingListViewModel

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search title", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            List(selection: $viewModel.selectedMeetingId) {
                ForEach(viewModel.filteredMeetings) { meeting in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(meeting.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(meeting.status.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(meeting.id)
                    .padding(.vertical, 4)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
