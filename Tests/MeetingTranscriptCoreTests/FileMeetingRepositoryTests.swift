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
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("2026-07-04-1400-tgb-sit/transcript.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("2026-07-04-1400-tgb-sit/metadata.json").path))
    }

    func testSaveRefreshesMarkdownWhenSpeakerNameChanges() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        var document = Self.sampleDocument()
        try repository.save(document)

        document.speakers[0].name = "Gavin"
        try repository.save(document)

        let markdownURL = root.appendingPathComponent("2026-07-04-1400-tgb-sit/transcript.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Gavin：今天先確認 SIT 測試範圍。"))
        XCTAssertFalse(markdown.contains("Speaker 1：今天先確認 SIT 測試範圍。"))
    }

    func testListsMeetingsFromMetadata() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())

        let meetings = try repository.listMeetings()

        XCTAssertEqual(meetings.map(\.id), ["2026-07-04-1400-tgb-sit"])
        XCTAssertEqual(meetings[0].title, "TGB SIT 進度會議")
    }

    func testRejectsInvalidMeetingIdsBeforeCreatingFiles() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let invalidIds = ["", ".", "..", "../escaped", "nested/id", "nested\\id", "meeting id", "會議"]

        for meetingId in invalidIds {
            XCTAssertThrowsError(try repository.meetingDirectory(for: meetingId))
            XCTAssertThrowsError(try repository.createMeetingDirectory(meetingId: meetingId))
            XCTAssertThrowsError(try repository.loadTranscript(meetingId: meetingId))

            let document = Self.sampleDocument(id: meetingId)
            XCTAssertThrowsError(try repository.save(document))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testListMeetingsSkipsCorruptMetadata() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())

        let corruptDirectory = root.appendingPathComponent("2026-07-04-1500-corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: corruptDirectory.appendingPathComponent("metadata.json"))

        let meetings = try repository.listMeetings()

        XCTAssertEqual(meetings.map(\.id), ["2026-07-04-1400-tgb-sit"])
    }

    func testListMeetingsSortsRecordedAtDescendingThenIdAscending() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let newest = ISO8601DateFormatter().date(from: "2026-07-04T15:00:00+08:00")!
        let tied = ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!

        try repository.save(Self.sampleDocument(id: "2026-07-04-1400-zeta", recordedAt: tied))
        try repository.save(Self.sampleDocument(id: "2026-07-04-1400-alpha", recordedAt: tied))
        try repository.save(Self.sampleDocument(id: "2026-07-04-1500-newest", recordedAt: newest))

        let meetings = try repository.listMeetings()

        XCTAssertEqual(meetings.map(\.id), [
            "2026-07-04-1500-newest",
            "2026-07-04-1400-alpha",
            "2026-07-04-1400-zeta"
        ])
    }

    func testSavesAndLoadsSummaryMarkdown() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        let meetingId = "2026-07-04-1400-tgb-sit"

        try repository.saveSummary("# 摘要\n\n- 決議：開始 SIT。", meetingId: meetingId)
        let loaded = try repository.loadSummary(meetingId: meetingId)

        XCTAssertEqual(loaded, "# 摘要\n\n- 決議：開始 SIT。")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(meetingId)/summary.md").path))
    }

    func testLoadSummaryReturnsNilWhenSummaryDoesNotExist() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)

        let loaded = try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit")

        XCTAssertNil(loaded)
    }

    func testSummaryRejectsInvalidMeetingIds() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)

        XCTAssertThrowsError(try repository.saveSummary("summary", meetingId: "../escaped"))
        XCTAssertThrowsError(try repository.loadSummary(meetingId: "../escaped"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped").path))
    }

    private static func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func sampleDocument(
        id: String = "2026-07-04-1400-tgb-sit",
        recordedAt: Date = ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!
    ) -> TranscriptDocument {
        TranscriptDocument(
            meeting: Meeting(
                id: id,
                title: "TGB SIT 進度會議",
                recordedAt: recordedAt,
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
