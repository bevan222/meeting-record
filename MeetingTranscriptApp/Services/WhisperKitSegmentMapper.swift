import Foundation
import MeetingTranscriptCore

struct WhisperKitMappedSegment {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

enum WhisperKitSegmentMapper {
    static func map(_ segments: [WhisperKitMappedSegment], fallbackText: String? = nil) -> [TranscriptSegment] {
        let mappedSegments = segments
            .map { segment in
                WhisperKitMappedSegment(
                    start: segment.start,
                    end: segment.end,
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }

        if mappedSegments.isEmpty,
           let fallbackText = fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackText.isEmpty {
            return [
                TranscriptSegment(id: "seg_0001", start: 0, end: 0, speakerId: nil, text: fallbackText, confidence: nil)
            ]
        }

        return mappedSegments.enumerated().map { index, segment in
            TranscriptSegment(
                id: String(format: "seg_%04d", index + 1),
                start: segment.start,
                end: segment.end,
                speakerId: nil,
                text: segment.text,
                confidence: nil
            )
        }
    }
}
