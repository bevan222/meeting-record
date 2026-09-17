import Foundation
import MeetingTranscriptCore

protocol TranscriptBuilding: Sendable {
    func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument
    func buildTranscript(
        for meeting: Meeting,
        audioURL: URL,
        onStatusChange: (@MainActor @Sendable (MeetingProcessingState) async -> Void)?
    ) async throws -> TranscriptDocument
}

extension TranscriptBuilding {
    func buildTranscript(
        for meeting: Meeting,
        audioURL: URL,
        onStatusChange: (@MainActor @Sendable (MeetingProcessingState) async -> Void)?
    ) async throws -> TranscriptDocument {
        try await buildTranscript(for: meeting, audioURL: audioURL)
    }
}

extension MeetingWorkflow: TranscriptBuilding {}
