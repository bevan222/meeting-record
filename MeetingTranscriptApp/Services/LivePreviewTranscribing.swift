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
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension)

        try FileManager.default.copyItem(at: audioURL, to: snapshotURL)
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        return try await transcriptionEngine.transcribe(
            audioURL: snapshotURL,
            options: TranscriptionOptions(language: language)
        )
    }
}
