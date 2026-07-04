import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class AppContainer: ObservableObject {
    let repository: FileMeetingRepository
    let workflow: MeetingWorkflow<WhisperKitTranscriptionEngine, MockDiarizationEngine>
    let markdownExporter: MarkdownTranscriptExporter
    let jsonExporter: JSONTranscriptExporter

    let meetingListViewModel: MeetingListViewModel
    let meetingDetailViewModel: MeetingDetailViewModel

    convenience init() {
        self.init(repository: FileMeetingRepository(rootDirectory: AppDirectories.meetingsDirectory()))
    }

    init(repository: FileMeetingRepository) {
        let markdownExporter = MarkdownTranscriptExporter()

        self.repository = repository
        self.workflow = MeetingWorkflow(
            transcriptionEngine: WhisperKitTranscriptionEngine(),
            diarizationEngine: MockDiarizationEngine(),
            assembler: TranscriptAssembler()
        )
        self.markdownExporter = markdownExporter
        self.jsonExporter = JSONTranscriptExporter()
        self.meetingListViewModel = MeetingListViewModel(repository: repository)
        self.meetingDetailViewModel = MeetingDetailViewModel(repository: repository, markdownExporter: markdownExporter)
    }
}
