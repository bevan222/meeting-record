import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingListViewModel: ObservableObject {
    @Published var meetings: [MeetingMetadata] = []
    @Published var selectedMeetingId: String?
    @Published var searchText = ""
    @Published var errorMessage: String?

    private let repository: FileMeetingRepository

    init(repository: FileMeetingRepository) {
        self.repository = repository
    }

    var filteredMeetings: [MeetingMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return meetings
        }

        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(query)
        }
    }

    func reload() {
        do {
            meetings = try repository.listMeetings()
            errorMessage = nil

            if let selectedMeetingId, meetings.contains(where: { $0.id == selectedMeetingId }) {
                return
            }
            selectedMeetingId = meetings.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
