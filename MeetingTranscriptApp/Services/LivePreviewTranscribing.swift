import Foundation
import MeetingTranscriptCore

protocol LivePreviewTranscribing: Sendable {
    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment]
}

struct WhisperKitLivePreviewTranscriber: LivePreviewTranscribing {
    private let transcriptionEngine: any TranscriptionEngine

    init(transcriptionEngine: any TranscriptionEngine = WhisperKitTranscriptionEngine()) {
        self.transcriptionEngine = transcriptionEngine
    }

    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioURL.path) else {
            throw LivePreviewTranscriberError.sourceMissing
        }

        let attributes = try fileManager.attributesOfItem(atPath: audioURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize > 0 else {
            throw LivePreviewTranscriberError.sourceEmpty
        }

        let snapshotURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension)

        try fileManager.copyItem(at: audioURL, to: snapshotURL)
        defer { try? fileManager.removeItem(at: snapshotURL) }

        return try await transcriptionEngine.transcribe(
            audioURL: snapshotURL,
            options: TranscriptionOptions(language: language)
        )
    }
}

enum LivePreviewTranscriberError: LocalizedError {
    case sourceMissing
    case sourceEmpty

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "Audio preview source does not exist."
        case .sourceEmpty:
            return "Audio preview source is empty."
        }
    }
}
