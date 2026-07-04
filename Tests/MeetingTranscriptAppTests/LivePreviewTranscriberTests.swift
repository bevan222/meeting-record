import Foundation
import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

final class LivePreviewTranscriberTests: XCTestCase {
    func testTranscribePreviewSnapshotsSourceAndCleansUpSnapshot() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try Data("audio".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let engine = CapturingTranscriptionEngine()
        let transcriber = WhisperKitLivePreviewTranscriber(transcriptionEngine: engine)

        let segments = try await transcriber.transcribePreview(audioURL: sourceURL, language: "zh-TW")

        let captured = await engine.snapshot()
        let capturedURL = try XCTUnwrap(captured.audioURL)
        XCTAssertNotEqual(capturedURL, sourceURL)
        XCTAssertEqual(capturedURL.pathExtension, "m4a")
        XCTAssertEqual(captured.options, TranscriptionOptions(language: "zh-TW"))
        XCTAssertEqual(captured.data, Data("audio".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: capturedURL.path))
        XCTAssertEqual(segments, [.previewSegment])
    }

    func testTranscribePreviewRejectsEmptySourceWithoutCallingEngine() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let engine = CapturingTranscriptionEngine()
        let transcriber = WhisperKitLivePreviewTranscriber(transcriptionEngine: engine)

        do {
            _ = try await transcriber.transcribePreview(audioURL: sourceURL, language: "zh-TW")
            XCTFail("Expected empty preview source to throw.")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "Audio preview source is empty.")
        }

        let captured = await engine.snapshot()
        XCTAssertEqual(captured.callCount, 0)
    }
}

private actor CapturingTranscriptionEngine: TranscriptionEngine {
    private(set) var callCount = 0
    private(set) var capturedAudioURL: URL?
    private(set) var capturedOptions: TranscriptionOptions?
    private(set) var capturedData: Data?

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> [TranscriptSegment] {
        callCount += 1
        capturedAudioURL = audioURL
        capturedOptions = options
        capturedData = try Data(contentsOf: audioURL)
        return [.previewSegment]
    }

    func snapshot() -> (callCount: Int, audioURL: URL?, options: TranscriptionOptions?, data: Data?) {
        (callCount, capturedAudioURL, capturedOptions, capturedData)
    }
}

private extension TranscriptSegment {
    static let previewSegment = TranscriptSegment(
        id: "seg_0001",
        start: 0,
        end: 1,
        speakerId: nil,
        text: "Preview",
        confidence: nil
    )
}
