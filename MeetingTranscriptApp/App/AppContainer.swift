import Combine
import Foundation
import MeetingTranscriptCore

@MainActor
final class AppContainer: ObservableObject {
    let repository: FileMeetingRepository
    let workflow: any TranscriptBuilding
    let livePreviewTranscriber: any LivePreviewTranscribing
    let summaryGenerator: any CodexSummaryGenerating
    let markdownExporter: MarkdownTranscriptExporter
    let jsonExporter: JSONTranscriptExporter

    let meetingListViewModel: MeetingListViewModel
    let meetingDetailViewModel: MeetingDetailViewModel

    convenience init() {
        self.init(
            repository: FileMeetingRepository(rootDirectory: AppDirectories.meetingsDirectory()),
            workflow: MeetingWorkflow(
                transcriptionEngine: WhisperKitTranscriptionEngine(),
                diarizationEngine: SpeakerKitDiarizationEngine(),
                assembler: TranscriptAssembler()
            ),
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber(),
            summaryGenerator: CodexCLISummaryGenerator()
        )
    }

    init(
        repository: FileMeetingRepository,
        workflow: any TranscriptBuilding,
        livePreviewTranscriber: any LivePreviewTranscribing,
        summaryGenerator: any CodexSummaryGenerating = CodexCLISummaryGenerator()
    ) {
        let markdownExporter = MarkdownTranscriptExporter()

        self.repository = repository
        self.workflow = workflow
        self.livePreviewTranscriber = livePreviewTranscriber
        self.summaryGenerator = summaryGenerator
        self.markdownExporter = markdownExporter
        self.jsonExporter = JSONTranscriptExporter()
        self.meetingListViewModel = MeetingListViewModel(repository: repository)
        self.meetingDetailViewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: markdownExporter,
            summaryGenerator: summaryGenerator
        )
    }

    convenience init(repository: FileMeetingRepository, workflow: any TranscriptBuilding) {
        self.init(
            repository: repository,
            workflow: workflow,
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber(),
            summaryGenerator: CodexCLISummaryGenerator()
        )
    }

    convenience init(repository: FileMeetingRepository) {
        self.init(
            repository: repository,
            workflow: MeetingWorkflow(
                transcriptionEngine: WhisperKitTranscriptionEngine(),
                diarizationEngine: SpeakerKitDiarizationEngine(),
                assembler: TranscriptAssembler()
            ),
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber(),
            summaryGenerator: CodexCLISummaryGenerator()
        )
    }
}
