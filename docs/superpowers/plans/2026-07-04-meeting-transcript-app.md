# Meeting Transcript App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working slice of the local macOS meeting transcript app: SwiftUI shell, real microphone recording to `audio.m4a`, local meeting storage, mock transcript/diarization, JSON/Markdown export, and speaker renaming.

**Architecture:** Use a Swift package with a pure `MeetingTranscriptCore` library and a `MeetingTranscriptApp` SwiftUI executable target. Core owns domain models, mock engines, speaker assembly, file repository, and exporters; the app target owns SwiftUI, Application Support paths, microphone permission, and `AVAudioRecorder`.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, SwiftUI, Foundation, AVFoundation.

---

## File Structure

Create these files:

```text
Package.swift
Sources/MeetingTranscriptCore/Models/MeetingModels.swift
Sources/MeetingTranscriptCore/Models/ProcessingState.swift
Sources/MeetingTranscriptCore/Ports/Engines.swift
Sources/MeetingTranscriptCore/Adapters/TranscriptAssembler.swift
Sources/MeetingTranscriptCore/Adapters/TranscriptExporters.swift
Sources/MeetingTranscriptCore/Adapters/MockEngines.swift
Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift
Sources/MeetingTranscriptCore/UseCases/MeetingWorkflow.swift
MeetingTranscriptApp/App/MeetingTranscriptApp.swift
MeetingTranscriptApp/App/AppContainer.swift
MeetingTranscriptApp/Services/AppDirectories.swift
MeetingTranscriptApp/Services/MacAudioRecorder.swift
MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift
MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift
MeetingTranscriptApp/UI/ContentView.swift
MeetingTranscriptApp/UI/MeetingListView.swift
MeetingTranscriptApp/UI/MeetingDetailView.swift
MeetingTranscriptApp/UI/RecordingToolbarView.swift
MeetingTranscriptApp/UI/TranscriptSegmentRow.swift
MeetingTranscriptApp/Resources/Info.plist
MeetingTranscriptApp/Resources/MeetingTranscriptApp.entitlements
Tests/MeetingTranscriptCoreTests/MeetingModelsTests.swift
Tests/MeetingTranscriptCoreTests/TranscriptExportersTests.swift
Tests/MeetingTranscriptCoreTests/TranscriptAssemblerTests.swift
Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift
Tests/MeetingTranscriptCoreTests/MeetingWorkflowTests.swift
```

`FileMeetingRepository` lives in Core because it only uses Foundation and is easiest to test there. `AppDirectories` remains in the app target and supplies the Application Support root path.

---

### Task 1: Swift Package Skeleton And Domain Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/MeetingTranscriptCore/Models/ProcessingState.swift`
- Create: `Sources/MeetingTranscriptCore/Models/MeetingModels.swift`
- Create: `Tests/MeetingTranscriptCoreTests/MeetingModelsTests.swift`

- [ ] **Step 1: Write the model tests**

Create `Tests/MeetingTranscriptCoreTests/MeetingModelsTests.swift`:

```swift
import XCTest
@testable import MeetingTranscriptCore

final class MeetingModelsTests: XCTestCase {
    func testTranscriptDocumentRoundTripsThroughJSON() throws {
        let document = TranscriptDocument(
            meeting: Meeting(
                id: "2026-07-04-1400-tgb-sit",
                title: "TGB SIT 進度會議",
                recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
                durationSeconds: 3600,
                language: "zh-TW",
                sourceAudio: "audio.m4a",
                status: .speakerAttributed
            ),
            speakers: [
                Speaker(id: "speaker_1", label: "Speaker 1", name: nil),
                Speaker(id: "speaker_2", label: "Speaker 2", name: "Gavin")
            ],
            segments: [
                TranscriptSegment(id: "seg_0001", start: 3.2, end: 8.1, speakerId: "speaker_1", text: "今天先確認 SIT 測試範圍。", confidence: nil)
            ]
        )

        let encoder = JSONEncoder.transcriptEncoder
        let decoder = JSONDecoder.transcriptDecoder
        let data = try encoder.encode(document)
        let decoded = try decoder.decode(TranscriptDocument.self, from: data)

        XCTAssertEqual(decoded.meeting.id, "2026-07-04-1400-tgb-sit")
        XCTAssertEqual(decoded.meeting.status, .speakerAttributed)
        XCTAssertEqual(decoded.speakers[1].displayName, "Gavin")
        XCTAssertEqual(decoded.segments[0].speakerId, "speaker_1")
        XCTAssertEqual(decoded.segments[0].text, "今天先確認 SIT 測試範圍。")
    }

    func testSpeakerDisplayNameUsesNameBeforeLabel() {
        XCTAssertEqual(Speaker(id: "speaker_1", label: "Speaker 1", name: "Gavin").displayName, "Gavin")
        XCTAssertEqual(Speaker(id: "speaker_1", label: "Speaker 1", name: nil).displayName, "Speaker 1")
        XCTAssertEqual(Speaker(id: "speaker_1", label: "Speaker 1", name: "").displayName, "Speaker 1")
    }
}
```

- [ ] **Step 2: Create package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingTranscriptApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MeetingTranscriptCore", targets: ["MeetingTranscriptCore"]),
        .executable(name: "MeetingTranscriptApp", targets: ["MeetingTranscriptApp"])
    ],
    targets: [
        .target(
            name: "MeetingTranscriptCore",
            path: "Sources/MeetingTranscriptCore"
        ),
        .executableTarget(
            name: "MeetingTranscriptApp",
            dependencies: ["MeetingTranscriptCore"],
            path: "MeetingTranscriptApp",
            exclude: ["Resources/Info.plist", "Resources/MeetingTranscriptApp.entitlements"]
        ),
        .testTarget(
            name: "MeetingTranscriptCoreTests",
            dependencies: ["MeetingTranscriptCore"],
            path: "Tests/MeetingTranscriptCoreTests"
        )
    ]
)
```

- [ ] **Step 3: Implement processing state**

Create `Sources/MeetingTranscriptCore/Models/ProcessingState.swift`:

```swift
import Foundation

public enum MeetingProcessingState: String, Codable, Equatable, Sendable, CaseIterable {
    case created
    case recording
    case recorded
    case transcribing
    case transcribed
    case diarizing
    case speakerAttributed
    case exported
    case failed
}
```

- [ ] **Step 4: Implement meeting models**

Create `Sources/MeetingTranscriptCore/Models/MeetingModels.swift`:

```swift
import Foundation

public struct Meeting: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var recordedAt: Date
    public var durationSeconds: TimeInterval
    public var language: String
    public var sourceAudio: String
    public var status: MeetingProcessingState

    public init(id: String, title: String, recordedAt: Date, durationSeconds: TimeInterval, language: String, sourceAudio: String, status: MeetingProcessingState) {
        self.id = id
        self.title = title
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.language = language
        self.sourceAudio = sourceAudio
        self.status = status
    }
}

public struct Speaker: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var name: String?

    public var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return label
        }
        return name
    }

    public init(id: String, label: String, name: String?) {
        self.id = id
        self.label = label
        self.name = name
    }
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var speakerId: String?
    public var text: String
    public var confidence: Double?

    public init(id: String, start: TimeInterval, end: TimeInterval, speakerId: String?, text: String, confidence: Double?) {
        self.id = id
        self.start = start
        self.end = end
        self.speakerId = speakerId
        self.text = text
        self.confidence = confidence
    }
}

public struct SpeakerTurn: Codable, Equatable, Sendable {
    public var speakerId: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Double?

    public init(speakerId: String, start: TimeInterval, end: TimeInterval, confidence: Double?) {
        self.speakerId = speakerId
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct TranscriptDocument: Codable, Equatable, Sendable {
    public var meeting: Meeting
    public var speakers: [Speaker]
    public var segments: [TranscriptSegment]

    public init(meeting: Meeting, speakers: [Speaker], segments: [TranscriptSegment]) {
        self.meeting = meeting
        self.speakers = speakers
        self.segments = segments
    }
}

public extension JSONEncoder {
    static var transcriptEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var transcriptDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter MeetingModelsTests
```

Expected: all `MeetingModelsTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/MeetingTranscriptCore/Models Tests/MeetingTranscriptCoreTests/MeetingModelsTests.swift
git commit -m "feat: add transcript domain models"
```

---

### Task 2: JSON And Markdown Exporters

**Files:**
- Create: `Sources/MeetingTranscriptCore/Adapters/TranscriptExporters.swift`
- Create: `Tests/MeetingTranscriptCoreTests/TranscriptExportersTests.swift`

- [ ] **Step 1: Write exporter tests**

Create `Tests/MeetingTranscriptCoreTests/TranscriptExportersTests.swift`:

```swift
import XCTest
@testable import MeetingTranscriptCore

final class TranscriptExportersTests: XCTestCase {
    func testJSONExporterProducesDecodableTranscript() throws {
        let document = Self.sampleDocument()
        let data = try JSONTranscriptExporter().export(document)
        let decoded = try JSONDecoder.transcriptDecoder.decode(TranscriptDocument.self, from: data)

        XCTAssertEqual(decoded.meeting.id, document.meeting.id)
        XCTAssertEqual(decoded.segments.count, 2)
        XCTAssertEqual(decoded.speakers[0].label, "Speaker 1")
    }

    func testMarkdownExporterFormatsMetadataAndSegments() throws {
        let markdown = MarkdownTranscriptExporter().export(Self.sampleDocument())

        XCTAssertTrue(markdown.contains("# TGB SIT 進度會議逐字稿"))
        XCTAssertTrue(markdown.contains("- 時間：2026-07-04 14:00"))
        XCTAssertTrue(markdown.contains("- 長度：1 分鐘"))
        XCTAssertTrue(markdown.contains("- 語言：zh-TW"))
        XCTAssertTrue(markdown.contains("- 音檔：audio.m4a"))
        XCTAssertTrue(markdown.contains("[00:00:03] Gavin：今天先確認 SIT 測試範圍。"))
        XCTAssertTrue(markdown.contains("[00:00:08] Speaker 2：API 還有兩支沒測完。"))
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
            speakers: [
                Speaker(id: "speaker_1", label: "Speaker 1", name: "Gavin"),
                Speaker(id: "speaker_2", label: "Speaker 2", name: nil)
            ],
            segments: [
                TranscriptSegment(id: "seg_0001", start: 3.2, end: 8.1, speakerId: "speaker_1", text: "今天先確認 SIT 測試範圍。", confidence: nil),
                TranscriptSegment(id: "seg_0002", start: 8.2, end: 15.0, speakerId: "speaker_2", text: "API 還有兩支沒測完。", confidence: nil)
            ]
        )
    }
}
```

- [ ] **Step 2: Implement exporters**

Create `Sources/MeetingTranscriptCore/Adapters/TranscriptExporters.swift`:

```swift
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
```

- [ ] **Step 3: Run tests**

Run:

```bash
swift test --filter TranscriptExportersTests
```

Expected: all `TranscriptExportersTests` pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/MeetingTranscriptCore/Adapters/TranscriptExporters.swift Tests/MeetingTranscriptCoreTests/TranscriptExportersTests.swift
git commit -m "feat: add transcript exporters"
```

---

### Task 3: Speaker Assembly And Mock Engines

**Files:**
- Create: `Sources/MeetingTranscriptCore/Ports/Engines.swift`
- Create: `Sources/MeetingTranscriptCore/Adapters/TranscriptAssembler.swift`
- Create: `Sources/MeetingTranscriptCore/Adapters/MockEngines.swift`
- Create: `Tests/MeetingTranscriptCoreTests/TranscriptAssemblerTests.swift`

- [ ] **Step 1: Write assembler tests**

Create `Tests/MeetingTranscriptCoreTests/TranscriptAssemblerTests.swift`:

```swift
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
```

- [ ] **Step 2: Define engine protocols**

Create `Sources/MeetingTranscriptCore/Ports/Engines.swift`:

```swift
import Foundation

public struct TranscriptionOptions: Equatable, Sendable {
    public var language: String

    public init(language: String) {
        self.language = language
    }
}

public struct DiarizationOptions: Equatable, Sendable {
    public var speakerCountHint: Int?

    public init(speakerCountHint: Int?) {
        self.speakerCountHint = speakerCountHint
    }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> [TranscriptSegment]
}

public protocol DiarizationEngine: Sendable {
    func diarize(audioURL: URL, options: DiarizationOptions) async throws -> [SpeakerTurn]
}
```

- [ ] **Step 3: Implement assembler**

Create `Sources/MeetingTranscriptCore/Adapters/TranscriptAssembler.swift`:

```swift
import Foundation

public struct TranscriptAssembler: Sendable {
    public init() {}

    public func assignSpeakers(to segments: [TranscriptSegment], using turns: [SpeakerTurn]) -> [TranscriptSegment] {
        segments.map { segment in
            var copy = segment
            copy.speakerId = bestSpeakerId(for: segment, turns: turns)
            return copy
        }
    }

    public func speakers(from turns: [SpeakerTurn]) -> [Speaker] {
        let ids = Set(turns.map(\.speakerId)).sorted()
        return ids.enumerated().map { index, id in
            Speaker(id: id, label: "Speaker \(index + 1)", name: nil)
        }
    }

    private func bestSpeakerId(for segment: TranscriptSegment, turns: [SpeakerTurn]) -> String? {
        let ranked = turns.compactMap { turn -> (speakerId: String, overlap: TimeInterval)? in
            let overlap = min(segment.end, turn.end) - max(segment.start, turn.start)
            return overlap > 0 ? (turn.speakerId, overlap) : nil
        }

        return ranked.max { lhs, rhs in
            lhs.overlap < rhs.overlap
        }?.speakerId
    }
}
```

- [ ] **Step 4: Implement mock engines**

Create `Sources/MeetingTranscriptCore/Adapters/MockEngines.swift`:

```swift
import Foundation

public struct MockTranscriptionEngine: TranscriptionEngine {
    public init() {}

    public func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> [TranscriptSegment] {
        [
            TranscriptSegment(id: "seg_0001", start: 3.0, end: 8.0, speakerId: nil, text: "今天先確認 SIT 測試範圍。", confidence: 1.0),
            TranscriptSegment(id: "seg_0002", start: 8.0, end: 15.0, speakerId: nil, text: "API 還有兩支沒測完。", confidence: 1.0),
            TranscriptSegment(id: "seg_0003", start: 15.0, end: 22.0, speakerId: nil, text: "那先排優先順序。", confidence: 1.0)
        ]
    }
}

public struct MockDiarizationEngine: DiarizationEngine {
    public init() {}

    public func diarize(audioURL: URL, options: DiarizationOptions) async throws -> [SpeakerTurn] {
        [
            SpeakerTurn(speakerId: "speaker_1", start: 0, end: 8, confidence: 1.0),
            SpeakerTurn(speakerId: "speaker_2", start: 8, end: 15, confidence: 1.0),
            SpeakerTurn(speakerId: "speaker_1", start: 15, end: 22, confidence: 1.0)
        ]
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter TranscriptAssemblerTests
```

Expected: all `TranscriptAssemblerTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeetingTranscriptCore/Ports Sources/MeetingTranscriptCore/Adapters/TranscriptAssembler.swift Sources/MeetingTranscriptCore/Adapters/MockEngines.swift Tests/MeetingTranscriptCoreTests/TranscriptAssemblerTests.swift
git commit -m "feat: add speaker assembly and mock engines"
```

---

### Task 4: File Repository And Workflow Use Cases

**Files:**
- Create: `Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift`
- Create: `Sources/MeetingTranscriptCore/UseCases/MeetingWorkflow.swift`
- Create: `Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift`
- Create: `Tests/MeetingTranscriptCoreTests/MeetingWorkflowTests.swift`

- [ ] **Step 1: Write repository tests**

Create `Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift`:

```swift
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
```

- [ ] **Step 2: Write workflow tests**

Create `Tests/MeetingTranscriptCoreTests/MeetingWorkflowTests.swift`:

```swift
import XCTest
@testable import MeetingTranscriptCore

final class MeetingWorkflowTests: XCTestCase {
    func testRunsMockTranscriptionDiarizationAndSpeakerRename() async throws {
        let meeting = Meeting(
            id: "2026-07-04-1400-tgb-sit",
            title: "TGB SIT 進度會議",
            recordedAt: ISO8601DateFormatter().date(from: "2026-07-04T14:00:00+08:00")!,
            durationSeconds: 22,
            language: "zh-TW",
            sourceAudio: "audio.m4a",
            status: .recorded
        )
        let workflow = MeetingWorkflow(
            transcriptionEngine: MockTranscriptionEngine(),
            diarizationEngine: MockDiarizationEngine(),
            assembler: TranscriptAssembler()
        )

        var document = try await workflow.buildTranscript(for: meeting, audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"))
        document = workflow.renameSpeaker("speaker_1", to: "Gavin", in: document)

        XCTAssertEqual(document.meeting.status, .speakerAttributed)
        XCTAssertEqual(document.speakers.first { $0.id == "speaker_1" }?.name, "Gavin")
        XCTAssertEqual(document.segments[0].speakerId, "speaker_1")
        XCTAssertEqual(document.segments.count, 3)
    }
}
```

- [ ] **Step 3: Implement file repository**

Create `Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift`:

```swift
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
        try markdown.write(to: directory.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
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
```

- [ ] **Step 4: Implement workflow**

Create `Sources/MeetingTranscriptCore/UseCases/MeetingWorkflow.swift`:

```swift
import Foundation

public struct MeetingWorkflow<T: TranscriptionEngine, D: DiarizationEngine>: Sendable {
    private let transcriptionEngine: T
    private let diarizationEngine: D
    private let assembler: TranscriptAssembler

    public init(transcriptionEngine: T, diarizationEngine: D, assembler: TranscriptAssembler) {
        self.transcriptionEngine = transcriptionEngine
        self.diarizationEngine = diarizationEngine
        self.assembler = assembler
    }

    public func buildTranscript(for meeting: Meeting, audioURL: URL) async throws -> TranscriptDocument {
        var transcribingMeeting = meeting
        transcribingMeeting.status = .transcribing

        let rawSegments = try await transcriptionEngine.transcribe(
            audioURL: audioURL,
            options: TranscriptionOptions(language: meeting.language)
        )

        var diarizingMeeting = transcribingMeeting
        diarizingMeeting.status = .diarizing

        let turns = try await diarizationEngine.diarize(
            audioURL: audioURL,
            options: DiarizationOptions(speakerCountHint: nil)
        )

        let speakers = assembler.speakers(from: turns)
        let segments = assembler.assignSpeakers(to: rawSegments, using: turns)

        var attributedMeeting = diarizingMeeting
        attributedMeeting.status = .speakerAttributed

        return TranscriptDocument(meeting: attributedMeeting, speakers: speakers, segments: segments)
    }

    public func renameSpeaker(_ speakerId: String, to name: String, in document: TranscriptDocument) -> TranscriptDocument {
        var copy = document
        copy.speakers = copy.speakers.map { speaker in
            guard speaker.id == speakerId else { return speaker }
            var renamed = speaker
            renamed.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
            return renamed
        }
        return copy
    }
}
```

- [ ] **Step 5: Run repository and workflow tests**

Run:

```bash
swift test --filter FileMeetingRepositoryTests
swift test --filter MeetingWorkflowTests
```

Expected: both test classes pass.

- [ ] **Step 6: Run all core tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeetingTranscriptCore/Storage Sources/MeetingTranscriptCore/UseCases Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift Tests/MeetingTranscriptCoreTests/MeetingWorkflowTests.swift
git commit -m "feat: add meeting repository and workflow"
```

---

### Task 5: SwiftUI App Shell With Meeting Library

**Files:**
- Create: `MeetingTranscriptApp/App/MeetingTranscriptApp.swift`
- Create: `MeetingTranscriptApp/App/AppContainer.swift`
- Create: `MeetingTranscriptApp/Services/AppDirectories.swift`
- Create: `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`
- Create: `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift`
- Create: `MeetingTranscriptApp/UI/ContentView.swift`
- Create: `MeetingTranscriptApp/UI/MeetingListView.swift`
- Create: `MeetingTranscriptApp/UI/MeetingDetailView.swift`
- Create: `MeetingTranscriptApp/UI/TranscriptSegmentRow.swift`

- [ ] **Step 1: Implement app entry and dependency container**

Create `MeetingTranscriptApp/App/MeetingTranscriptApp.swift`:

```swift
import SwiftUI

@main
struct MeetingTranscriptApplication: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
        }
        .windowStyle(.titleBar)
    }
}
```

Create `MeetingTranscriptApp/App/AppContainer.swift`:

```swift
import Foundation
import MeetingTranscriptCore

@MainActor
final class AppContainer: ObservableObject {
    let repository: FileMeetingRepository
    let workflow: MeetingWorkflow<MockTranscriptionEngine, MockDiarizationEngine>
    let markdownExporter: MarkdownTranscriptExporter
    let jsonExporter: JSONTranscriptExporter

    init() {
        let meetingsRoot = AppDirectories.meetingsDirectory()
        self.repository = FileMeetingRepository(rootDirectory: meetingsRoot)
        self.workflow = MeetingWorkflow(
            transcriptionEngine: MockTranscriptionEngine(),
            diarizationEngine: MockDiarizationEngine(),
            assembler: TranscriptAssembler()
        )
        self.markdownExporter = MarkdownTranscriptExporter()
        self.jsonExporter = JSONTranscriptExporter()
    }
}
```

Create `MeetingTranscriptApp/Services/AppDirectories.swift`:

```swift
import Foundation

enum AppDirectories {
    static func meetingsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingTranscriptApp", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
```

- [ ] **Step 2: Implement view models**

Create `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`:

```swift
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingListViewModel: ObservableObject {
    @Published var meetings: [MeetingMetadata] = []
    @Published var selectedMeetingId: String?
    @Published var searchText = ""
    @Published var errorMessage: String?

    private let repository: FileMeetingRepository

    init(repository: FileMeetingRepository) {
        self.repository = repository
    }

    var filteredMeetings: [MeetingMetadata] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return meetings
        }
        return meetings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func reload() {
        do {
            meetings = try repository.listMeetings()
            if selectedMeetingId == nil {
                selectedMeetingId = meetings.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

Create `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift`:

```swift
import Foundation
import MeetingTranscriptCore

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    @Published var document: TranscriptDocument?
    @Published var errorMessage: String?

    private let repository: FileMeetingRepository
    private let markdownExporter: MarkdownTranscriptExporter

    init(repository: FileMeetingRepository, markdownExporter: MarkdownTranscriptExporter) {
        self.repository = repository
        self.markdownExporter = markdownExporter
    }

    func load(meetingId: String?) {
        guard let meetingId else {
            document = nil
            return
        }
        do {
            document = try repository.loadTranscript(meetingId: meetingId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSegmentText(segmentId: String, text: String) {
        guard var document else { return }
        document.segments = document.segments.map { segment in
            guard segment.id == segmentId else { return segment }
            var copy = segment
            copy.text = text
            return copy
        }
        save(document)
    }

    func renameSpeaker(speakerId: String, name: String) {
        guard var document else { return }
        document.speakers = document.speakers.map { speaker in
            guard speaker.id == speakerId else { return speaker }
            var copy = speaker
            copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
            return copy
        }
        save(document)
    }

    func exportMarkdown() {
        guard let document else { return }
        do {
            try repository.saveMarkdown(markdownExporter.export(document), meetingId: document.meeting.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ document: TranscriptDocument) {
        do {
            try repository.save(document)
            self.document = document
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Implement SwiftUI views**

Create `MeetingTranscriptApp/UI/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var listViewModelHolder = Holder<MeetingListViewModel>()
    @StateObject private var detailViewModelHolder = Holder<MeetingDetailViewModel>()

    var body: some View {
        let listViewModel = listViewModelHolder.value ?? MeetingListViewModel(repository: container.repository)
        let detailViewModel = detailViewModelHolder.value ?? MeetingDetailViewModel(repository: container.repository, markdownExporter: container.markdownExporter)

        NavigationSplitView {
            MeetingListView(viewModel: listViewModel)
                .frame(minWidth: 260)
        } detail: {
            MeetingDetailView(viewModel: detailViewModel, selectedMeetingId: listViewModel.selectedMeetingId)
        }
        .onAppear {
            listViewModelHolder.value = listViewModel
            detailViewModelHolder.value = detailViewModel
            listViewModel.reload()
        }
        .onChange(of: listViewModel.selectedMeetingId) { _, newValue in
            detailViewModel.load(meetingId: newValue)
        }
    }
}

@MainActor
final class Holder<T: ObservableObject>: ObservableObject {
    var value: T?
}
```

Create `MeetingTranscriptApp/UI/MeetingListView.swift`:

```swift
import SwiftUI

struct MeetingListView: View {
    @ObservedObject var viewModel: MeetingListViewModel

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search title", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            List(selection: $viewModel.selectedMeetingId) {
                ForEach(viewModel.filteredMeetings) { meeting in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title)
                            .font(.headline)
                        Text(meeting.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(meeting.status.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(meeting.id)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
```

Create `MeetingTranscriptApp/UI/MeetingDetailView.swift`:

```swift
import SwiftUI
import MeetingTranscriptCore

struct MeetingDetailView: View {
    @ObservedObject var viewModel: MeetingDetailViewModel
    let selectedMeetingId: String?

    var body: some View {
        Group {
            if let document = viewModel.document {
                VStack(alignment: .leading, spacing: 0) {
                    header(document)
                    Divider()
                    List(document.segments) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            speakerName: speakerName(for: segment, in: document),
                            onTextChanged: { text in
                                viewModel.updateSegmentText(segmentId: segment.id, text: text)
                            }
                        )
                    }
                    Divider()
                    speakerEditor(document)
                    Divider()
                    HStack {
                        Button("Export Markdown") {
                            viewModel.exportMarkdown()
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No Meeting Selected", systemImage: "waveform", description: Text("Start a recording or select a saved meeting."))
            }
        }
        .onAppear {
            viewModel.load(meetingId: selectedMeetingId)
        }
    }

    private func header(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(document.meeting.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text("\(document.meeting.language) • \(Int(document.meeting.durationSeconds)) seconds • \(document.meeting.status.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func speakerEditor(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speakers")
                .font(.headline)
            ForEach(document.speakers) { speaker in
                HStack {
                    Text(speaker.label)
                    TextField("Name", text: Binding(
                        get: { speaker.name ?? "" },
                        set: { viewModel.renameSpeaker(speakerId: speaker.id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
    }

    private func speakerName(for segment: TranscriptSegment, in document: TranscriptDocument) -> String {
        guard let speakerId = segment.speakerId,
              let speaker = document.speakers.first(where: { $0.id == speakerId }) else {
            return "Unknown Speaker"
        }
        return speaker.displayName
    }
}
```

Create `MeetingTranscriptApp/UI/TranscriptSegmentRow.swift`:

```swift
import SwiftUI
import MeetingTranscriptCore

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let speakerName: String
    let onTextChanged: (String) -> Void
    @State private var text: String

    init(segment: TranscriptSegment, speakerName: String, onTextChanged: @escaping (String) -> Void) {
        self.segment = segment
        self.speakerName = speakerName
        self.onTextChanged = onTextChanged
        self._text = State(initialValue: segment.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timestamp(segment.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(speakerName)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 110, alignment: .leading)
            TextField("Transcript text", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .onSubmit {
                    onTextChanged(text)
                }
                .onChange(of: text) { _, newValue in
                    onTextChanged(newValue)
                }
        }
        .padding(.vertical, 6)
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }
}
```

- [ ] **Step 4: Build app target**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Run app manually**

Run:

```bash
swift run MeetingTranscriptApp
```

Expected: a macOS window opens with an empty state and meeting sidebar.

- [ ] **Step 6: Commit**

```bash
git add MeetingTranscriptApp Package.swift
git commit -m "feat: add SwiftUI meeting library shell"
```

---

### Task 6: Recording Service And Record/Stop Workflow

**Files:**
- Create: `MeetingTranscriptApp/Services/MacAudioRecorder.swift`
- Create: `MeetingTranscriptApp/UI/RecordingToolbarView.swift`
- Modify: `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`
- Modify: `MeetingTranscriptApp/UI/MeetingDetailView.swift`
- Create: `MeetingTranscriptApp/Resources/Info.plist`
- Create: `MeetingTranscriptApp/Resources/MeetingTranscriptApp.entitlements`

- [ ] **Step 1: Implement recorder service**

Create `MeetingTranscriptApp/Services/MacAudioRecorder.swift`:

```swift
import AVFoundation
import Foundation

@MainActor
final class MacAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case checkingPermission
        case permissionDenied
        case recording(startedAt: Date)
        case stopping
        case saved(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        state = .checkingPermission
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted {
            state = .permissionDenied
        }
        return granted
    }

    func startRecording(to url: URL) async {
        guard await requestPermission() else { return }

        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()
            state = .recording(startedAt: Date())
            startTimer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording() {
        guard recorder != nil else { return }
        state = .stopping
        recorder?.stop()
        stopTimer()
        if let url = recorder?.url {
            state = .saved(url)
        }
        recorder = nil
    }

    private func startTimer() {
        elapsedSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 2: Add Info.plist and entitlements files**

Create `MeetingTranscriptApp/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.meeting-transcript-app</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>MeetingTranscriptApp records meeting audio locally to create transcripts.</string>
</dict>
</plist>
```

Create `MeetingTranscriptApp/Resources/MeetingTranscriptApp.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Add recording toolbar view**

Create `MeetingTranscriptApp/UI/RecordingToolbarView.swift`:

```swift
import SwiftUI

struct RecordingToolbarView: View {
    @ObservedObject var recorder: MacAudioRecorder
    let onRecord: () -> Void
    let onStop: () -> Void

    private var isRecording: Bool {
        if case .recording = recorder.state {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onRecord()
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .disabled(isRecording)

            Button {
                onStop()
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!isRecording)

            Text(formatElapsed(recorder.elapsedSeconds))
                .font(.system(.body, design: .monospaced))

            Spacer()
        }
        .padding()
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }
}
```

- [ ] **Step 4: Extend list view model for recording**

Modify `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift` by adding these properties and methods inside the class:

```swift
@Published var recorder = MacAudioRecorder()

func startRecording(container: AppContainer) {
    let now = Date()
    let id = Self.makeMeetingId(date: now)
    let title = "Untitled Meeting"

    do {
        let meetingDirectory = try repository.createMeetingDirectory(meetingId: id)
        let audioURL = meetingDirectory.appendingPathComponent("audio.m4a")
        selectedMeetingId = id
        Task {
            await recorder.startRecording(to: audioURL)
        }
        let placeholder = TranscriptDocument(
            meeting: Meeting(id: id, title: title, recordedAt: now, durationSeconds: 0, language: "zh-TW", sourceAudio: "audio.m4a", status: .recording),
            speakers: [],
            segments: []
        )
        try repository.save(placeholder)
        reload()
    } catch {
        errorMessage = error.localizedDescription
    }
}

func stopRecording(container: AppContainer) {
    recorder.stopRecording()
    guard case .saved(let audioURL) = recorder.state else { return }
    Task {
        do {
            var meeting = Meeting(
                id: audioURL.deletingLastPathComponent().lastPathComponent,
                title: "Untitled Meeting",
                recordedAt: Date(),
                durationSeconds: recorder.elapsedSeconds,
                language: "zh-TW",
                sourceAudio: "audio.m4a",
                status: .recorded
            )
            meeting.status = .recorded
            let document = try await container.workflow.buildTranscript(for: meeting, audioURL: audioURL)
            try container.repository.save(document)
            await MainActor.run {
                self.selectedMeetingId = document.meeting.id
                self.reload()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

private static func makeMeetingId(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    return formatter.string(from: date) + "-meeting"
}
```

- [ ] **Step 5: Wire toolbar into detail view**

Modify `MeetingTranscriptApp/UI/MeetingDetailView.swift` so its initializer accepts recording actions:

```swift
struct MeetingDetailView: View {
    @ObservedObject var viewModel: MeetingDetailViewModel
    let selectedMeetingId: String?
    @ObservedObject var recorder: MacAudioRecorder
    let onRecord: () -> Void
    let onStop: () -> Void
```

Replace the body of `MeetingDetailView` with this structure so recording is available even when there is no selected meeting:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        RecordingToolbarView(
            recorder: recorder,
            onRecord: onRecord,
            onStop: onStop
        )
        Divider()

        Group {
            if let document = viewModel.document {
                VStack(alignment: .leading, spacing: 0) {
                    header(document)
                    Divider()
                    List(document.segments) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            speakerName: speakerName(for: segment, in: document),
                            onTextChanged: { text in
                                viewModel.updateSegmentText(segmentId: segment.id, text: text)
                            }
                        )
                    }
                    Divider()
                    speakerEditor(document)
                    Divider()
                    HStack {
                        Button("Export Markdown") {
                            viewModel.exportMarkdown()
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No Meeting Selected", systemImage: "waveform", description: Text("Start a recording or select a saved meeting."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    .onAppear {
        viewModel.load(meetingId: selectedMeetingId)
    }
}
```

Modify `MeetingTranscriptApp/UI/ContentView.swift` where `MeetingDetailView` is created:

```swift
MeetingDetailView(
    viewModel: detailViewModel,
    selectedMeetingId: listViewModel.selectedMeetingId,
    recorder: listViewModel.recorder,
    onRecord: { listViewModel.startRecording(container: container) },
    onStop: { listViewModel.stopRecording(container: container) }
)
```

- [ ] **Step 6: Build and test**

Run:

```bash
swift build
swift test
```

Expected: build succeeds and all tests pass.

- [ ] **Step 7: Manual recording check**

Run:

```bash
swift run MeetingTranscriptApp
```

Manual expected result:

- Window opens.
- Record starts a new meeting.
- Stop creates `audio.m4a` under `~/Library/Application Support/MeetingTranscriptApp/Meetings/<meeting-id>/`.
- The meeting appears in the sidebar after stop.
- The transcript area shows mock segments with `Speaker 1` / `Speaker 2`.

- [ ] **Step 8: Commit**

```bash
git add MeetingTranscriptApp
git commit -m "feat: add local audio recording workflow"
```

---

### Task 7: Export JSON, Export Markdown, And Open Folder Actions

**Files:**
- Modify: `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift`
- Modify: `MeetingTranscriptApp/UI/MeetingDetailView.swift`

- [ ] **Step 1: Add export and folder actions to detail view model**

Modify `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift` by adding:

```swift
func exportJSON() {
    guard let document else { return }
    do {
        try repository.save(document)
    } catch {
        errorMessage = error.localizedDescription
    }
}

func meetingFolderURL() -> URL? {
    guard let document else { return nil }
    return repository.meetingDirectory(for: document.meeting.id)
}
```

- [ ] **Step 2: Add buttons to detail view**

Modify the bottom `HStack` in `MeetingTranscriptApp/UI/MeetingDetailView.swift`:

```swift
HStack {
    Button("Export JSON") {
        viewModel.exportJSON()
    }
    Button("Export Markdown") {
        viewModel.exportMarkdown()
    }
    Button("Open Folder") {
        if let url = viewModel.meetingFolderURL() {
            NSWorkspace.shared.open(url)
        }
    }
    Spacer()
}
.padding()
```

Add the import at the top of the same file:

```swift
import AppKit
```

- [ ] **Step 3: Build and test**

Run:

```bash
swift build
swift test
```

Expected: build succeeds and all tests pass.

- [ ] **Step 4: Manual export check**

Run:

```bash
swift run MeetingTranscriptApp
```

Manual expected result:

- Select a meeting.
- Click `Export JSON`.
- Confirm `transcript.json` exists in the meeting folder.
- Click `Export Markdown`.
- Confirm `transcript.md` exists and contains `[00:00:03]`.
- Rename `Speaker 1` to `Gavin`, export Markdown again, and confirm the Markdown shows `Gavin`.

- [ ] **Step 5: Commit**

```bash
git add MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift MeetingTranscriptApp/UI/MeetingDetailView.swift
git commit -m "feat: add transcript export actions"
```

---

### Task 8: Final Verification And Documentation Update

**Files:**
- Modify: `docs/superpowers/specs/2026-07-04-meeting-transcript-app-design.md` only if implementation changes an approved behavior.
- Create: `README.md`

- [ ] **Step 1: Create README**

Create `README.md`:

```markdown
# MeetingTranscriptApp

Local macOS meeting transcript app MVP.

## First Slice

- SwiftUI macOS shell
- Local microphone recording to `audio.m4a`
- Local meeting folders under Application Support
- Canonical `transcript.json`
- Human-readable `transcript.md`
- Mock transcription and mock diarization adapters
- Speaker rename support

The first slice does not use cloud model APIs and does not integrate real WhisperKit or SpeakerKit models. Those are adapter implementations for the next phase.

## Commands

```bash
swift build
swift test
swift run MeetingTranscriptApp
```
```

- [ ] **Step 2: Run full verification**

Run:

```bash
swift build
swift test
git status --short
```

Expected:

- `swift build` succeeds.
- `swift test` succeeds.
- `git status --short` shows only `?? README.md` before staging.

- [ ] **Step 3: Manual MVP verification**

Run:

```bash
swift run MeetingTranscriptApp
```

Manual expected result:

- Fresh launch shows empty state.
- Record/Stop saves a playable `audio.m4a`.
- Meeting list reloads with the new meeting.
- Mock transcript segments appear.
- Speaker rename updates UI.
- `transcript.json` and `transcript.md` are present in the meeting folder.
- Restarting the app shows the meeting in the sidebar.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add app usage notes"
```

---

## Plan Self-Review

Spec coverage:

- SwiftUI macOS app shell: Task 5.
- Start/stop recording and real `audio.m4a`: Task 6.
- Meeting folders and local persistence: Task 4 and Task 6.
- `transcript.json`: Task 2 and Task 4.
- `transcript.md`: Task 2 and Task 7.
- Mock transcription and mock diarization adapters: Task 3 and Task 4.
- Speaker attribution and rename: Task 3, Task 4, Task 5, Task 7.
- Export actions: Task 7.
- No cloud model API: Package has no cloud dependency; mock engines are local Core types.
- WhisperKit/SpeakerKit deferred behind protocols: Task 3 protocols define the adapter boundary.

Placeholder scan:

- No `TBD`, `TODO`, or unspecified code blocks are intentionally left in this plan.
- Each code-changing step names the target file and provides the code to add or the exact code block to insert.

Type consistency:

- `MeetingProcessingState`, `Meeting`, `Speaker`, `TranscriptSegment`, `SpeakerTurn`, and `TranscriptDocument` are defined in Task 1 and used consistently afterward.
- `TranscriptionEngine`, `DiarizationEngine`, `TranscriptAssembler`, `MockTranscriptionEngine`, and `MockDiarizationEngine` are defined in Task 3 and used in Task 4 onward.
- `FileMeetingRepository` is defined in Task 4 and used by App view models in Task 5 onward.
