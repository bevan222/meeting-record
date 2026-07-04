import Foundation
import MeetingTranscriptCore
import SpeakerKit
import WhisperKit

struct SpeakerKitDiarizationEngine: MeetingTranscriptCore.DiarizationEngine {
    private let makeSpeakerKit: @Sendable () async throws -> SpeakerKit

    init(makeSpeakerKit: @escaping @Sendable () async throws -> SpeakerKit = {
        try await SpeakerKit()
    }) {
        self.makeSpeakerKit = makeSpeakerKit
    }

    func diarize(
        audioURL: URL,
        options: MeetingTranscriptCore.DiarizationOptions
    ) async throws -> [SpeakerTurn] {
        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        let speakerKit = try await makeSpeakerKit()
        let diarizationOptions = PyannoteDiarizationOptions(numberOfSpeakers: options.speakerCountHint)
        let result = try await speakerKit.diarize(audioArray: audioArray, options: diarizationOptions)
        let mappedTurns = result.segments.compactMap { segment -> SpeakerKitMappedTurn? in
            guard let speakerIndex = segment.speaker.speakerId else { return nil }
            return SpeakerKitMappedTurn(
                speakerIndex: speakerIndex,
                start: TimeInterval(segment.startTime),
                end: TimeInterval(segment.endTime)
            )
        }

        return SpeakerKitTurnMapper.map(mappedTurns)
    }
}
