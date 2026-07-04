import Foundation

enum AppDirectories {
    static func meetingsDirectory() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingTranscriptApp", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
