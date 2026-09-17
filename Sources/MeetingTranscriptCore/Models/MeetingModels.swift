import Foundation

public struct Meeting: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var recordedAt: Date
    public var durationSeconds: TimeInterval
    public var language: String
    public var sourceAudio: String
    public var status: MeetingProcessingState

    public init(id: String, title: String, recordedAt: Date, durationSeconds: TimeInterval, language: String, sourceAudio: String, status: MeetingProcessingState) {
        self.id = id
        self.title = title
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.language = language
        self.sourceAudio = sourceAudio
        self.status = status
    }
}

public struct Speaker: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var name: String?

    public var displayName: String {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedName.isEmpty else {
            return label
        }
        return trimmedName
    }

    public init(id: String, label: String, name: String?) {
        self.id = id
        self.label = label
        self.name = name
    }
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var speakerId: String?
    public var text: String
    public var confidence: Double?

    public init(id: String, start: TimeInterval, end: TimeInterval, speakerId: String?, text: String, confidence: Double?) {
        self.id = id
        self.start = start
        self.end = end
        self.speakerId = speakerId
        self.text = text
        self.confidence = confidence
    }
}

public struct SpeakerTurn: Codable, Equatable, Sendable {
    public var speakerId: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Double?

    public init(speakerId: String, start: TimeInterval, end: TimeInterval, confidence: Double?) {
        self.speakerId = speakerId
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct TranscriptDocument: Codable, Equatable, Sendable {
    public var meeting: Meeting
    public var speakers: [Speaker]
    public var segments: [TranscriptSegment]

    public init(meeting: Meeting, speakers: [Speaker], segments: [TranscriptSegment]) {
        self.meeting = meeting
        self.speakers = speakers
        self.segments = segments
    }
}

public extension JSONEncoder {
    static var transcriptEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var transcriptDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
