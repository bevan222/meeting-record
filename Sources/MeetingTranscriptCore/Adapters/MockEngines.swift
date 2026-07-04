import Foundation

public struct MockTranscriptionEngine: TranscriptionEngine {
    public init() {}

    public static var sampleSegments: [TranscriptSegment] {
        [
            TranscriptSegment(id: "seg_0001", start: 3.0, end: 8.0, speakerId: nil, text: "今天先確認 SIT 測試範圍。", confidence: 1.0),
            TranscriptSegment(id: "seg_0002", start: 8.0, end: 15.0, speakerId: nil, text: "API 還有兩支沒測完。", confidence: 1.0),
            TranscriptSegment(id: "seg_0003", start: 15.0, end: 22.0, speakerId: nil, text: "那先排優先順序。", confidence: 1.0)
        ]
    }

    public func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> [TranscriptSegment] {
        Self.sampleSegments
    }
}

public struct MockDiarizationEngine: DiarizationEngine {
    public init() {}

    public func diarize(audioURL: URL, options: DiarizationOptions) async throws -> [SpeakerTurn] {
        [
            SpeakerTurn(speakerId: "speaker_1", start: 0, end: 8, confidence: 1.0),
            SpeakerTurn(speakerId: "speaker_2", start: 8, end: 15, confidence: 1.0),
            SpeakerTurn(speakerId: "speaker_1", start: 15, end: 22, confidence: 1.0)
        ]
    }
}
