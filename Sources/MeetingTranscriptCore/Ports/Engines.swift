import Foundation

public struct TranscriptionOptions: Equatable, Sendable {
    public var language: String

    public init(language: String) {
        self.language = language
    }
}

public struct DiarizationOptions: Equatable, Sendable {
    public var speakerCountHint: Int?

    public init(speakerCountHint: Int?) {
        self.speakerCountHint = speakerCountHint
    }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> [TranscriptSegment]
}

public protocol DiarizationEngine: Sendable {
    func diarize(audioURL: URL, options: DiarizationOptions) async throws -> [SpeakerTurn]
}
