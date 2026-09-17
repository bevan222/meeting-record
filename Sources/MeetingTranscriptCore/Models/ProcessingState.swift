import Foundation

public enum MeetingProcessingState: String, Codable, Equatable, Sendable, CaseIterable {
    case created
    case recording
    case recorded
    case transcribing
    case transcribed
    case diarizing
    case speakerAttributed
    case exported
    case failed
}
