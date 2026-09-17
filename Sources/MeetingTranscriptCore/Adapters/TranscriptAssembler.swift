import Foundation

public struct TranscriptAssembler: Sendable {
    public init() {}

    public func assignSpeakers(to segments: [TranscriptSegment], using turns: [SpeakerTurn]) -> [TranscriptSegment] {
        segments.map { segment in
            var copy = segment
            copy.speakerId = bestSpeakerId(for: segment, turns: turns)
            return copy
        }
    }

    public func speakers(from turns: [SpeakerTurn]) -> [Speaker] {
        let ids = Set(turns.map(\.speakerId)).sorted()
        return ids.enumerated().map { index, id in
            Speaker(id: id, label: "Speaker \(index + 1)", name: nil)
        }
    }

    private func bestSpeakerId(for segment: TranscriptSegment, turns: [SpeakerTurn]) -> String? {
        let ranked = turns.compactMap { turn -> (speakerId: String, overlap: TimeInterval)? in
            let overlap = min(segment.end, turn.end) - max(segment.start, turn.start)
            return overlap > 0 ? (turn.speakerId, overlap) : nil
        }

        return ranked.max { lhs, rhs in
            lhs.overlap < rhs.overlap
        }?.speakerId
    }
}
