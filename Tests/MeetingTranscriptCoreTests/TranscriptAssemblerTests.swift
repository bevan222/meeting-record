import XCTest
@testable import MeetingTranscriptCore

final class TranscriptAssemblerTests: XCTestCase {
    func testAssignsSpeakerByLargestOverlap() {
        let segments = [
            TranscriptSegment(id: "seg_0001", start: 0, end: 5, speakerId: nil, text: "第一段", confidence: nil),
            TranscriptSegment(id: "seg_0002", start: 5, end: 10, speakerId: nil, text: "第二段", confidence: nil)
        ]
        let turns = [
            SpeakerTurn(speakerId: "speaker_1", start: 0, end: 6, confidence: nil),
            SpeakerTurn(speakerId: "speaker_2", start: 6, end: 10, confidence: nil)
        ]

        let assigned = TranscriptAssembler().assignSpeakers(to: segments, using: turns)

        XCTAssertEqual(assigned[0].speakerId, "speaker_1")
        XCTAssertEqual(assigned[1].speakerId, "speaker_2")
    }

    func testLeavesSpeakerNilWhenThereIsNoOverlap() {
        let segments = [
            TranscriptSegment(id: "seg_0001", start: 20, end: 25, speakerId: nil, text: "沒有重疊", confidence: nil)
        ]
        let turns = [
            SpeakerTurn(speakerId: "speaker_1", start: 0, end: 5, confidence: nil)
        ]

        let assigned = TranscriptAssembler().assignSpeakers(to: segments, using: turns)

        XCTAssertNil(assigned[0].speakerId)
    }

    func testBuildsSpeakersFromTurnsInStableOrder() {
        let turns = [
            SpeakerTurn(speakerId: "speaker_2", start: 5, end: 10, confidence: nil),
            SpeakerTurn(speakerId: "speaker_1", start: 0, end: 5, confidence: nil),
            SpeakerTurn(speakerId: "speaker_2", start: 10, end: 15, confidence: nil)
        ]

        let speakers = TranscriptAssembler().speakers(from: turns)

        XCTAssertEqual(speakers, [
            Speaker(id: "speaker_1", label: "Speaker 1", name: nil),
            Speaker(id: "speaker_2", label: "Speaker 2", name: nil)
        ])
    }
}
