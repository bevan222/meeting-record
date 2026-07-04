import Foundation
import MeetingTranscriptCore

protocol TranscriptBuilding: Sendable {
    func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument
}

extension MeetingWorkflow: TranscriptBuilding {}
