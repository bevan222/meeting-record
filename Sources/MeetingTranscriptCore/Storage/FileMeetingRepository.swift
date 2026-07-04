import Foundation

public struct MeetingMetadata: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var recordedAt: Date
    public var durationSeconds: TimeInterval
    public var language: String
    public var sourceAudio: String
    public var status: MeetingProcessingState
    public var hasSpeakerAttribution: Bool

    public init(document: TranscriptDocument) {
        self.id = document.meeting.id
        self.title = document.meeting.title
        self.recordedAt = document.meeting.recordedAt
        self.durationSeconds = document.meeting.durationSeconds
        self.language = document.meeting.language
        self.sourceAudio = document.meeting.sourceAudio
        self.status = document.meeting.status
        self.hasSpeakerAttribution = document.segments.contains { $0.speakerId != nil }
    }
}

public struct FileMeetingRepository: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func meetingDirectory(for meetingId: String) throws -> URL {
        let storageId = try Self.validatedStorageId(meetingId)
        return rootDirectory.appendingPathComponent(storageId, isDirectory: true)
    }

    public func createMeetingDirectory(meetingId: String) throws -> URL {
        let directory = try meetingDirectory(for: meetingId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func save(_ document: TranscriptDocument) throws {
        let directory = try createMeetingDirectory(meetingId: document.meeting.id)
        let transcriptURL = directory.appendingPathComponent("transcript.json")
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let markdownURL = directory.appendingPathComponent("transcript.md")

        try JSONEncoder.transcriptEncoder.encode(document).write(to: transcriptURL, options: .atomic)
        try JSONEncoder.transcriptEncoder.encode(MeetingMetadata(document: document)).write(to: metadataURL, options: .atomic)
        try MarkdownTranscriptExporter().export(document).write(to: markdownURL, atomically: true, encoding: .utf8)
    }

    public func saveMarkdown(_ markdown: String, meetingId: String) throws {
        let directory = try createMeetingDirectory(meetingId: meetingId)
        let markdownURL = directory.appendingPathComponent("transcript.md")
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
    }

    public func loadTranscript(meetingId: String) throws -> TranscriptDocument {
        let url = try meetingDirectory(for: meetingId).appendingPathComponent("transcript.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder.transcriptDecoder.decode(TranscriptDocument.self, from: data)
    }

    public func listMeetings() throws -> [MeetingMetadata] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }

        let directories = try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        let metadata = directories.compactMap { directory -> MeetingMetadata? in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }

            let metadataURL = directory.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }

            guard
                let data = try? Data(contentsOf: metadataURL),
                let metadata = try? JSONDecoder.transcriptDecoder.decode(MeetingMetadata.self, from: data),
                (try? Self.validatedStorageId(metadata.id)) != nil
            else {
                return nil
            }
            return metadata
        }

        return metadata.sorted { lhs, rhs in
            if lhs.recordedAt == rhs.recordedAt {
                return lhs.id < rhs.id
            }
            return lhs.recordedAt > rhs.recordedAt
        }
    }

    private static func validatedStorageId(_ meetingId: String) throws -> String {
        guard !meetingId.isEmpty,
              meetingId != ".",
              meetingId != "..",
              meetingId.unicodeScalars.allSatisfy(Self.isAllowedStorageIDScalar)
        else {
            throw FileMeetingRepositoryError.invalidMeetingId(meetingId)
        }
        return meetingId
    }

    private static func isAllowedStorageIDScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 45, 95:
            return true
        default:
            return false
        }
    }
}

public enum FileMeetingRepositoryError: Error, Equatable, Sendable {
    case invalidMeetingId(String)
}
