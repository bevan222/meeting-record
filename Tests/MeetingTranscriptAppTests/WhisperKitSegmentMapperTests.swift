import XCTest
@testable import MeetingTranscriptApp

final class WhisperKitSegmentMapperTests: XCTestCase {
    func testUsesTraditionalChinesePromptForChineseTranscription() throws {
        XCTAssertEqual(
            WhisperKitPrompt.prompt(for: "zh"),
            "以下是台灣繁體中文會議逐字稿。請使用繁體中文，不要使用簡體中文。"
        )
        XCTAssertNil(WhisperKitPrompt.prompt(for: "en"))
    }

    func testNormalizesBCP47LanguageForWhisperKit() throws {
        XCTAssertEqual(WhisperKitLanguageNormalizer.normalize("zh-TW"), "zh")
        XCTAssertEqual(WhisperKitLanguageNormalizer.normalize("zh-Hant-TW"), "zh")
        XCTAssertEqual(WhisperKitLanguageNormalizer.normalize("en-US"), "en")
        XCTAssertEqual(WhisperKitLanguageNormalizer.normalize(" ja "), "ja")
        XCTAssertNil(WhisperKitLanguageNormalizer.normalize(""))
    }

    func testMapsSegmentsToStableTranscriptSegments() throws {
        let segments = WhisperKitSegmentMapper.map([
            WhisperKitMappedSegment(start: 1.2, end: 3.4, text: "  今天先確認範圍。 "),
            WhisperKitMappedSegment(start: 3.4, end: 5.0, text: "API 還有兩支。")
        ])

        XCTAssertEqual(segments.map(\.id), ["seg_0001", "seg_0002"])
        XCTAssertEqual(segments[0].start, 1.2)
        XCTAssertEqual(segments[0].end, 3.4)
        XCTAssertNil(segments[0].speakerId)
        XCTAssertEqual(segments[0].text, "今天先確認範圍。")
        XCTAssertNil(segments[0].confidence)
        XCTAssertEqual(segments[1].text, "API 還有兩支。")
    }

    func testDropsWhitespaceOnlySegments() throws {
        let segments = WhisperKitSegmentMapper.map([
            WhisperKitMappedSegment(start: 0, end: 1, text: "   "),
            WhisperKitMappedSegment(start: 1, end: 2, text: "有效文字")
        ])

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].id, "seg_0001")
        XCTAssertEqual(segments[0].text, "有效文字")
    }

    func testMapsFullTextFallbackWhenSegmentsAreEmpty() throws {
        let segments = WhisperKitSegmentMapper.map([], fallbackText: "  沒有 segment 的全文。 ")

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].id, "seg_0001")
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[0].end, 0)
        XCTAssertEqual(segments[0].text, "沒有 segment 的全文。")
    }
}
