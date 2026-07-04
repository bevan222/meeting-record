import Foundation
import MeetingTranscriptCore

struct SpeakerKitMappedTurn: Equatable {
    let speakerIndex: Int
    let start: TimeInterval
    let end: TimeInterval
}

enum SpeakerKitTurnMapper {
    static func map(_ mappedTurns: [SpeakerKitMappedTurn]) -> [SpeakerTurn] {
        mappedTurns.compactMap { turn in
            guard turn.speakerIndex >= 0, turn.end > turn.start else { return nil }

            return SpeakerTurn(
                speakerId: "speaker_\(turn.speakerIndex + 1)",
                start: turn.start,
                end: turn.end,
                confidence: nil
            )
        }
    }
}
