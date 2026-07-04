import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class AppContainer: ObservableObject {
    let repository: FileMeetingRepository
    let workflow: MeetingWorkflow<MockTranscriptionEngine, MockDiarizationEngine>
    let markdownExporter: MarkdownTranscriptExporter
    let jsonExporter: JSONTranscriptExporter

    let meetingListViewModel: MeetingListViewModel
    let meetingDetailViewModel: MeetingDetailViewModel

    init() {
        let repository = FileMeetingRepository(rootDirectory: AppDirectories.meetingsDirectory())
        let markdownExporter = MarkdownTranscriptExporter()

        self.repository = repository
        self.workflow = MeetingWorkflow(
            transcriptionEngine: MockTranscriptionEngine(),
            diarizationEngine: MockDiarizationEngine(),
            assembler: TranscriptAssembler()
        )
        self.markdownExporter = markdownExporter
        self.jsonExporter = JSONTranscriptExporter()
        self.meetingListViewModel = MeetingListViewModel(repository: repository)
        self.meetingDetailViewModel = MeetingDetailViewModel(repository: repository, markdownExporter: markdownExporter)
    }
}
