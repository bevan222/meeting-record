import XCTest
@testable import MeetingTranscriptCore

final class FileMeetingRepositoryTests: XCTestCase {
    func testSavesAndLoadsTranscriptDocument() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let document = Self.sampleDocument()

        try repository.save(document)
        let loaded = try repository.loadTranscript(meetingId: document.meeting.id)

        XCTAssertEqual(loaded, document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("2026-07-04-1400-tgb-sit/transcript.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("2026-07-04-1400-tgb-sit/metadata.json").path))
    }

    func testListsMeetingsFromMetadata() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())

        let meetings = try repository.listMeetings()

        XCTAssertEqual(meetings.map(\.id), ["2026-07-04-1400-tgb-sit"])
        XCTAssertEqual(meetings[0].title, "TGB SIT 進度會議")
    }

    private static func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func sampleDocument() -> TranscriptDocument {
        TranscriptDocument(
            meeting: Meeting(
                id: "2026-07-04-1400-tgb-sit",
                title: "TGB SIT 進度會議",
                recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
                durationSeconds: 65,
                language: "zh-TW",
                sourceAudio: "audio.m4a",
                status: .speakerAttributed
            ),
            speakers: [Speaker(id: "speaker_1", label: "Speaker 1", name: nil)],
            segments: [TranscriptSegment(id: "seg_0001", start: 3, end: 8, speakerId: "speaker_1", text: "今天先確認 SIT 測試範圍。", confidence: nil)]
        )
    }
}
