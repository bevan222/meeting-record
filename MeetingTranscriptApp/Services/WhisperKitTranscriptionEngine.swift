import Foundation
import MeetingTranscriptCore
import WhisperKit

struct WhisperKitTranscriptionEngine: TranscriptionEngine {
    private let model: String

    init(model: String = "tiny") {
        self.model = model
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> [TranscriptSegment] {
        let config = WhisperKitConfig(model: model)
        let whisperKit = try await WhisperKit(config)
        let language = WhisperKitLanguageNormalizer.normalize(options.language)
        var decodeOptions = DecodingOptions(language: language)
        if let prompt = WhisperKitPrompt.prompt(for: language), let tokenizer = whisperKit.tokenizer {
            decodeOptions.promptTokens = tokenizer
                .encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            decodeOptions.usePrefillPrompt = true
        }
        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
        let mappedSegments = results.flatMap { result in
            result.segments.map { segment in
                WhisperKitMappedSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: segment.text
                )
            }
        }
        let fallbackText = results.map(\.text).joined(separator: " ")
        let segments = WhisperKitSegmentMapper.map(mappedSegments, fallbackText: fallbackText)

        guard !segments.isEmpty else {
            throw WhisperKitTranscriptionEngineError.emptyTranscript
        }

        return segments
    }
}

enum WhisperKitTranscriptionEngineError: LocalizedError {
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "WhisperKit did not produce any transcript text."
        }
    }
}
