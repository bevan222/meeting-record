import Foundation

public struct JSONTranscriptExporter: Sendable {
    public init() {}

    public func export(_ document: TranscriptDocument) throws -> Data {
        try JSONEncoder.transcriptEncoder.encode(document)
    }
}

public struct MarkdownTranscriptExporter: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        self.calendar = calendar
    }

    public func export(_ document: TranscriptDocument) -> String {
        let speakerNames = Dictionary(uniqueKeysWithValues: document.speakers.map { ($0.id, $0.displayName) })
        let header = [
            "# \(document.meeting.title)逐字稿",
            "",
            "- 時間：\(formatDate(document.meeting.recordedAt))",
            "- 長度：\(Int(ceil(document.meeting.durationSeconds / 60))) 分鐘",
            "- 語言：\(document.meeting.language)",
            "- 音檔：\(document.meeting.sourceAudio)",
            "",
            "## 逐字稿",
            ""
        ].joined(separator: "\n")

        let body = document.segments.map { segment in
            let speaker = segment.speakerId.flatMap { speakerNames[$0] } ?? "Unknown Speaker"
            return "[\(formatTimestamp(segment.start))] \(speaker)：\(segment.text)"
        }.joined(separator: "\n")

        return header + body + "\n"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
