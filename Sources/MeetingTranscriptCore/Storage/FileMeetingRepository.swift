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

    public func meetingDirectory(for meetingId: String) -> URL {
        rootDirectory.appendingPathComponent(meetingId, isDirectory: true)
    }

    public func createMeetingDirectory(meetingId: String) throws -> URL {
        let directory = meetingDirectory(for: meetingId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func save(_ document: TranscriptDocument) throws {
        let directory = try createMeetingDirectory(meetingId: document.meeting.id)
        let transcriptURL = directory.appendingPathComponent("transcript.json")
        let metadataURL = directory.appendingPathComponent("metadata.json")

        try JSONEncoder.transcriptEncoder.encode(document).write(to: transcriptURL, options: .atomic)
        try JSONEncoder.transcriptEncoder.encode(MeetingMetadata(document: document)).write(to: metadataURL, options: .atomic)
    }

    public func saveMarkdown(_ markdown: String, meetingId: String) throws {
        let directory = try createMeetingDirectory(meetingId: meetingId)
        let markdownURL = directory.appendingPathComponent("transcript.md")
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
    }

    public func loadTranscript(meetingId: String) throws -> TranscriptDocument {
        let url = meetingDirectory(for: meetingId).appendingPathComponent("transcript.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder.transcriptDecoder.decode(TranscriptDocument.self, from: data)
    }

    public func listMeetings() throws -> [MeetingMetadata] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }

        let directories = try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        let metadata = try directories.compactMap { directory -> MeetingMetadata? in
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }

            let metadataURL = directory.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }

            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder.transcriptDecoder.decode(MeetingMetadata.self, from: data)
        }

        return metadata.sorted { $0.recordedAt > $1.recordedAt }
    }
}
