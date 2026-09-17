import XCTest
@testable import MeetingTranscriptApp

final class SpeakerKitTurnMapperTests: XCTestCase {
    func testMapsZeroBasedSpeakerKitIndexesToOneBasedSpeakerIds() throws {
        let turns = SpeakerKitTurnMapper.map([
            SpeakerKitMappedTurn(speakerIndex: 0, start: 0.5, end: 3.0),
            SpeakerKitMappedTurn(speakerIndex: 1, start: 3.0, end: 6.2)
        ])

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].speakerId, "speaker_1")
        XCTAssertEqual(turns[0].start, 0.5)
        XCTAssertEqual(turns[0].end, 3.0)
        XCTAssertNil(turns[0].confidence)
        XCTAssertEqual(turns[1].speakerId, "speaker_2")
    }

    func testDropsInvalidSpeakerKitTurns() throws {
        let turns = SpeakerKitTurnMapper.map([
            SpeakerKitMappedTurn(speakerIndex: -1, start: 0, end: 1),
            SpeakerKitMappedTurn(speakerIndex: 0, start: 2, end: 2),
            SpeakerKitMappedTurn(speakerIndex: 1, start: 4, end: 3),
            SpeakerKitMappedTurn(speakerIndex: 2, start: 5, end: 7)
        ])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].speakerId, "speaker_3")
        XCTAssertEqual(turns[0].start, 5)
        XCTAssertEqual(turns[0].end, 7)
    }
}
