import Foundation

public struct MeetingWorkflow<T: TranscriptionEngine, D: DiarizationEngine>: Sendable {
    private let transcriptionEngine: T
    private let diarizationEngine: D
    private let assembler: TranscriptAssembler

    public init(transcriptionEngine: T, diarizationEngine: D, assembler: TranscriptAssembler) {
        self.transcriptionEngine = transcriptionEngine
        self.diarizationEngine = diarizationEngine
        self.assembler = assembler
    }

    public func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument {
        try await buildTranscript(for: meeting, audioURL: audioURL, onStatusChange: nil)
    }

    public func buildTranscript(
        for meeting: Meeting,
        audioURL: URL,
        onStatusChange: (@MainActor @Sendable (MeetingProcessingState) async -> Void)?
    ) async throws -> TranscriptDocument {
        var transcribingMeeting = meeting
        transcribingMeeting.status = .transcribing
        await onStatusChange?(.transcribing)

        let rawSegments = try await transcriptionEngine.transcribe(
            audioURL: audioURL,
            options: TranscriptionOptions(language: meeting.language)
        )

        var diarizingMeeting = transcribingMeeting
        diarizingMeeting.status = .diarizing
        await onStatusChange?(.diarizing)

        let turns = try await diarizationEngine.diarize(
            audioURL: audioURL,
            options: DiarizationOptions(speakerCountHint: nil)
        )

        let speakers = assembler.speakers(from: turns)
        let segments = assembler.assignSpeakers(to: rawSegments, using: turns)

        var attributedMeeting = diarizingMeeting
        attributedMeeting.status = .speakerAttributed

        return TranscriptDocument(meeting: attributedMeeting, speakers: speakers, segments: segments)
    }

    public func renameSpeaker(_ speakerId: String, to name: String, in document: TranscriptDocument) -> TranscriptDocument {
        var copy = document
        copy.speakers = copy.speakers.map { speaker in
            guard speaker.id == speakerId else { return speaker }

            var renamed = speaker
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            renamed.name = trimmedName.isEmpty ? nil : trimmedName
            return renamed
        }
        return copy
    }
}
