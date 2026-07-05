# Codex Summary Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app `用 Codex 整理摘要` action that sends the selected meeting transcript to Codex CLI and saves the returned Markdown as `summary.md`.

**Architecture:** Keep canonical transcript storage in `MeetingTranscriptCore`. Add summary persistence helpers to `FileMeetingRepository`, add an app-layer Codex summary generator around non-interactive `codex exec`, then wire it into `MeetingDetailViewModel` and `MeetingDetailView`. Codex receives transcript content and returns text only; the app writes `summary.md`.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Foundation `Process`, Codex CLI non-interactive `exec`.

---

## File Structure

- Modify `Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift`
  - Add `saveSummary(_:meetingId:)` and `loadSummary(meetingId:)`.
- Modify `Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift`
  - Cover summary save/load and missing summary behavior.
- Create `MeetingTranscriptApp/Services/CodexSummaryGenerating.swift`
  - Define the app-layer protocol and CLI generator.
  - Define a small command runner protocol so tests do not launch real Codex.
  - Implement the production `Process` runner.
- Create `Tests/MeetingTranscriptAppTests/CodexSummaryGeneratorTests.swift`
  - Cover prompt content, `codex exec` arguments, non-zero exit handling, empty output handling, and temp cleanup behavior through a fake runner.
- Modify `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift`
  - Add summary state and async summary generation action.
- Modify `Tests/MeetingTranscriptAppTests/MeetingDetailViewModelTests.swift`
  - Cover success, failure, no-segment guard, existing summary load, and no overwrite on failure.
- Modify `MeetingTranscriptApp/App/AppContainer.swift`
  - Inject the production summary generator into `MeetingDetailViewModel`.
- Modify `MeetingTranscriptApp/UI/MeetingDetailView.swift`
  - Add the button, running state, disabled state, and read-only summary display.
- Modify `README.md`
  - Document that summary generation uses Codex CLI and writes `summary.md`.

---

### Task 1: Add Summary Persistence To Repository

**Files:**
- Modify: `Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift`
- Modify: `Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift`

- [ ] **Step 1: Add failing repository tests**

Add these tests to `Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift` before `makeTemporaryRoot()`:

```swift
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
```

- [ ] **Step 2: Run repository summary tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter FileMeetingRepositoryTests/testSavesAndLoadsSummaryMarkdown --filter FileMeetingRepositoryTests/testLoadSummaryReturnsNilWhenSummaryDoesNotExist --filter FileMeetingRepositoryTests/testSummaryRejectsInvalidMeetingIds
```

Expected: FAIL because `FileMeetingRepository` does not define `saveSummary` or `loadSummary`.

- [ ] **Step 3: Implement summary helpers**

Add these methods to `Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift` after `saveMarkdown`:

```swift
    public func saveSummary(_ summary: String, meetingId: String) throws {
        let directory = try createMeetingDirectory(meetingId: meetingId)
        let summaryURL = directory.appendingPathComponent("summary.md")
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
    }

    public func loadSummary(meetingId: String) throws -> String? {
        let summaryURL = try meetingDirectory(for: meetingId).appendingPathComponent("summary.md")
        guard FileManager.default.fileExists(atPath: summaryURL.path) else {
            return nil
        }
        return try String(contentsOf: summaryURL, encoding: .utf8)
    }
```

- [ ] **Step 4: Run repository summary tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter FileMeetingRepositoryTests/testSavesAndLoadsSummaryMarkdown --filter FileMeetingRepositoryTests/testLoadSummaryReturnsNilWhenSummaryDoesNotExist --filter FileMeetingRepositoryTests/testSummaryRejectsInvalidMeetingIds
```

Expected: PASS for the 3 new repository tests.

- [ ] **Step 5: Commit repository summary persistence**

Run:

```bash
git add Sources/MeetingTranscriptCore/Storage/FileMeetingRepository.swift Tests/MeetingTranscriptCoreTests/FileMeetingRepositoryTests.swift
git commit -m "feat: persist meeting summaries"
```

---

### Task 2: Add Codex CLI Summary Generator

**Files:**
- Create: `MeetingTranscriptApp/Services/CodexSummaryGenerating.swift`
- Create: `Tests/MeetingTranscriptAppTests/CodexSummaryGeneratorTests.swift`

- [ ] **Step 1: Add failing Codex generator tests**

Create `Tests/MeetingTranscriptAppTests/CodexSummaryGeneratorTests.swift`:

```swift
import XCTest
@testable import MeetingTranscriptApp
@testable import MeetingTranscriptCore

final class CodexSummaryGeneratorTests: XCTestCase {
    func testGeneratorSendsTraditionalChinesePromptAndTranscriptJSONToCodexExec() async throws {
        let runner = FakeCodexCommandRunner(output: "# 摘要\n\n- 重點：確認 SIT。")
        let executableURL = try Self.makeExecutableFile()
        let generator = CodexCLISummaryGenerator(
            executableURL: executableURL,
            commandRunner: runner
        )

        let summary = try await generator.generateSummary(
            for: Self.sampleDocument(),
            meetingDirectory: URL(fileURLWithPath: "/tmp/meeting", isDirectory: true)
        )

        XCTAssertEqual(summary, "# 摘要\n\n- 重點：確認 SIT。")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executableURL.path, executableURL.path)
        XCTAssertEqual(runner.calls[0].workingDirectory.path, "/tmp/meeting")
        XCTAssertEqual(runner.calls[0].arguments, [
            "exec",
            "--skip-git-repo-check",
            "--output-last-message",
            runner.calls[0].outputFileURL.path,
            "-"
        ])
        XCTAssertTrue(runner.calls[0].prompt.contains("請根據以下會議逐字稿整理"))
        XCTAssertTrue(runner.calls[0].prompt.contains("請使用繁體中文，輸出 Markdown。"))
        XCTAssertTrue(runner.calls[0].prompt.contains("\"title\" : \"TGB SIT 進度會議\""))
        XCTAssertTrue(runner.calls[0].prompt.contains("\"text\" : \"今天先確認 SIT 測試範圍。\""))
    }

    func testGeneratorThrowsReadableErrorWhenCodexExitsNonZero() async throws {
        let runner = FakeCodexCommandRunner(
            output: "",
            result: CodexCommandResult(terminationStatus: 1, standardError: "login required")
        )
        let executableURL = try Self.makeExecutableFile()
        let generator = CodexCLISummaryGenerator(
            executableURL: executableURL,
            commandRunner: runner
        )

        do {
            _ = try await generator.generateSummary(
                for: Self.sampleDocument(),
                meetingDirectory: URL(fileURLWithPath: "/tmp/meeting", isDirectory: true)
            )
            XCTFail("Expected Codex summary generation to fail.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Codex CLI failed: login required")
        }
    }

    func testGeneratorRejectsEmptySummaryOutput() async throws {
        let runner = FakeCodexCommandRunner(output: " \n ")
        let executableURL = try Self.makeExecutableFile()
        let generator = CodexCLISummaryGenerator(
            executableURL: executableURL,
            commandRunner: runner
        )

        do {
            _ = try await generator.generateSummary(
                for: Self.sampleDocument(),
                meetingDirectory: URL(fileURLWithPath: "/tmp/meeting", isDirectory: true)
            )
            XCTFail("Expected empty summary output to fail.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Codex CLI returned an empty summary.")
        }
    }

    private static func makeExecutableFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: url)
        return url
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
            speakers: [Speaker(id: "speaker_1", label: "Speaker 1", name: "Gavin")],
            segments: [
                TranscriptSegment(
                    id: "seg_0001",
                    start: 3,
                    end: 8,
                    speakerId: "speaker_1",
                    text: "今天先確認 SIT 測試範圍。",
                    confidence: nil
                )
            ]
        )
    }
}

private final class FakeCodexCommandRunner: CodexCommandRunning, @unchecked Sendable {
    struct Call {
        let executableURL: URL
        let arguments: [String]
        let workingDirectory: URL
        let outputFileURL: URL
        let prompt: String
    }

    private let output: String
    private let result: CodexCommandResult
    private(set) var calls: [Call] = []

    init(
        output: String,
        result: CodexCommandResult = CodexCommandResult(terminationStatus: 0, standardError: "")
    ) {
        self.output = output
        self.result = result
    }

    func runCodex(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        outputFileURL: URL,
        prompt: String
    ) async throws -> CodexCommandResult {
        calls.append(
            Call(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                outputFileURL: outputFileURL,
                prompt: prompt
            )
        )
        try output.write(to: outputFileURL, atomically: true, encoding: .utf8)
        return result
    }
}
```

- [ ] **Step 2: Run Codex generator tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter CodexSummaryGeneratorTests
```

Expected: FAIL because `CodexSummaryGenerating`, `CodexCLISummaryGenerator`, `CodexCommandRunning`, and `CodexCommandResult` do not exist.

- [ ] **Step 3: Implement Codex generator and runner**

Create `MeetingTranscriptApp/Services/CodexSummaryGenerating.swift`:

```swift
import Foundation
import MeetingTranscriptCore

protocol CodexSummaryGenerating: Sendable {
    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String
}

struct CodexCommandResult: Sendable {
    let terminationStatus: Int32
    let standardError: String
}

protocol CodexCommandRunning: Sendable {
    func runCodex(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        outputFileURL: URL,
        prompt: String
    ) async throws -> CodexCommandResult
}

struct CodexCLISummaryGenerator: CodexSummaryGenerating {
    private let executableURL: URL
    private let commandRunner: any CodexCommandRunning

    init(
        executableURL: URL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
        commandRunner: any CodexCommandRunning = ProcessCodexCommandRunner()
    ) {
        self.executableURL = executableURL
        self.commandRunner = commandRunner
    }

    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw CodexSummaryError.executableMissing(executableURL.path)
        }

        let outputFileURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        defer { try? fileManager.removeItem(at: outputFileURL) }

        let arguments = [
            "exec",
            "--skip-git-repo-check",
            "--output-last-message",
            outputFileURL.path,
            "-"
        ]
        let result = try await commandRunner.runCodex(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: meetingDirectory,
            outputFileURL: outputFileURL,
            prompt: try Self.makePrompt(for: document)
        )

        guard result.terminationStatus == 0 else {
            throw CodexSummaryError.commandFailed(result.standardError)
        }

        let summary = try String(contentsOf: outputFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw CodexSummaryError.emptyOutput
        }
        return summary
    }

    static func makePrompt(for document: TranscriptDocument) throws -> String {
        let data = try JSONEncoder.transcriptEncoder.encode(document)
        let json = String(decoding: data, as: UTF8.self)
        return """
        請根據以下會議逐字稿整理：
        1. 重點摘要
        2. 決議事項
        3. 待辦事項
        4. 負責人
        5. 期限
        6. 未解問題

        請使用繁體中文，輸出 Markdown。

        ```json
        \(json)
        ```
        """
    }
}

struct ProcessCodexCommandRunner: CodexCommandRunning {
    func runCodex(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        outputFileURL: URL,
        prompt: String
    ) async throws -> CodexCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            let inputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardError = errorPipe

            try process.run()
            if let inputData = prompt.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
            }
            try? inputPipe.fileHandleForWriting.close()

            process.waitUntilExit()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let standardError = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return CodexCommandResult(
                terminationStatus: process.terminationStatus,
                standardError: standardError
            )
        }.value
    }
}

enum CodexSummaryError: LocalizedError, Equatable {
    case executableMissing(String)
    case commandFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "Codex CLI was not found at \(path)."
        case .commandFailed(let stderr):
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "Codex CLI failed." : "Codex CLI failed: \(message)"
        case .emptyOutput:
            return "Codex CLI returned an empty summary."
        }
    }
}
```

- [ ] **Step 4: Run Codex generator tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter CodexSummaryGeneratorTests
```

Expected: PASS for all `CodexSummaryGeneratorTests`.

- [ ] **Step 5: Commit Codex generator**

Run:

```bash
git add MeetingTranscriptApp/Services/CodexSummaryGenerating.swift Tests/MeetingTranscriptAppTests/CodexSummaryGeneratorTests.swift
git commit -m "feat: add codex summary generator"
```

---

### Task 3: Wire Summary Generation Into Detail View Model

**Files:**
- Modify: `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift`
- Modify: `MeetingTranscriptApp/App/AppContainer.swift`
- Modify: `Tests/MeetingTranscriptAppTests/MeetingDetailViewModelTests.swift`

- [ ] **Step 1: Add failing view model tests**

Add this fake generator to the bottom of `Tests/MeetingTranscriptAppTests/MeetingDetailViewModelTests.swift`:

```swift
private final class FakeSummaryGenerator: CodexSummaryGenerating, @unchecked Sendable {
    enum Mode {
        case success(String)
        case failure(Error)
    }

    private let mode: Mode
    private(set) var requestedDocuments: [TranscriptDocument] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func generateSummary(for document: TranscriptDocument, meetingDirectory: URL) async throws -> String {
        requestedDocuments.append(document)
        switch mode {
        case .success(let summary):
            return summary
        case .failure(let error):
            throw error
        }
    }
}

private enum TestSummaryError: LocalizedError {
    case failed

    var errorDescription: String? {
        "summary failed"
    }
}
```

Add these tests before `makeTemporaryRoot()`:

```swift
    func testLoadReadsExistingSummaryMarkdown() throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        try repository.saveSummary("# 舊摘要", meetingId: "2026-07-04-1400-tgb-sit")
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .success("# 新摘要"))
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")

        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
    }

    func testGenerateSummarySavesPublishesAndUsesLatestTranscript() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        let generator = FakeSummaryGenerator(mode: .success("# 摘要\n\n- 決議：開始 SIT。"))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        _ = viewModel.updateMeetingTitle("TGB SIT API 測試會議")
        await viewModel.generateSummary()

        let loadedSummary = try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit")
        XCTAssertEqual(loadedSummary, "# 摘要\n\n- 決議：開始 SIT。")
        XCTAssertEqual(viewModel.summaryMarkdown, "# 摘要\n\n- 決議：開始 SIT。")
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertEqual(viewModel.isGeneratingSummary, false)
        XCTAssertEqual(generator.requestedDocuments.first?.meeting.title, "TGB SIT API 測試會議")
    }

    func testGenerateSummaryFailureKeepsExistingSummary() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        try repository.save(Self.sampleDocument())
        try repository.saveSummary("# 舊摘要", meetingId: "2026-07-04-1400-tgb-sit")
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: FakeSummaryGenerator(mode: .failure(TestSummaryError.failed))
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        await viewModel.generateSummary()

        XCTAssertEqual(try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit"), "# 舊摘要")
        XCTAssertEqual(viewModel.summaryMarkdown, "# 舊摘要")
        XCTAssertEqual(viewModel.errorMessage, "summary failed")
        XCTAssertEqual(viewModel.isGeneratingSummary, false)
    }

    func testGenerateSummaryRefusesDocumentWithoutSegments() async throws {
        let root = try Self.makeTemporaryRoot()
        let repository = FileMeetingRepository(rootDirectory: root)
        var document = Self.sampleDocument()
        document.segments = []
        try repository.save(document)
        let generator = FakeSummaryGenerator(mode: .success("# 摘要"))
        let viewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: MarkdownTranscriptExporter(),
            summaryGenerator: generator
        )

        viewModel.load(meetingId: "2026-07-04-1400-tgb-sit")
        await viewModel.generateSummary()

        XCTAssertNil(try repository.loadSummary(meetingId: "2026-07-04-1400-tgb-sit"))
        XCTAssertNil(viewModel.summaryMarkdown)
        XCTAssertEqual(viewModel.errorMessage, "No transcript segments are available for summary.")
        XCTAssertTrue(generator.requestedDocuments.isEmpty)
    }
```

- [ ] **Step 2: Run view model summary tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingDetailViewModelTests/testLoadReadsExistingSummaryMarkdown --filter MeetingDetailViewModelTests/testGenerateSummary
```

Expected: FAIL because `MeetingDetailViewModel` does not expose summary state, does not accept `summaryGenerator`, and does not define `generateSummary()`.

- [ ] **Step 3: Update detail view model**

Modify `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift` so the stored properties and initializer become:

```swift
    @Published var document: TranscriptDocument?
    @Published var summaryMarkdown: String?
    @Published var isGeneratingSummary = false
    @Published var errorMessage: String?

    private let repository: FileMeetingRepository
    private let markdownExporter: MarkdownTranscriptExporter
    private let summaryGenerator: any CodexSummaryGenerating

    init(
        repository: FileMeetingRepository,
        markdownExporter: MarkdownTranscriptExporter,
        summaryGenerator: any CodexSummaryGenerating
    ) {
        self.repository = repository
        self.markdownExporter = markdownExporter
        self.summaryGenerator = summaryGenerator
    }
```

Update `load(meetingId:)` to clear and load summary:

```swift
    func load(meetingId: String?) {
        guard let meetingId else {
            document = nil
            summaryMarkdown = nil
            errorMessage = nil
            return
        }

        do {
            document = try repository.loadTranscript(meetingId: meetingId)
            summaryMarkdown = try repository.loadSummary(meetingId: meetingId)
            errorMessage = nil
        } catch {
            document = nil
            summaryMarkdown = nil
            errorMessage = error.localizedDescription
        }
    }
```

Add this public computed property and async action before `meetingFolderURL()`:

```swift
    var canGenerateSummary: Bool {
        guard let document else { return false }
        return !document.segments.isEmpty && !isGeneratingSummary
    }

    func generateSummary() async {
        guard !isGeneratingSummary else { return }
        guard let document else { return }
        guard !document.segments.isEmpty else {
            errorMessage = "No transcript segments are available for summary."
            return
        }

        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        guard save(document) else { return }

        do {
            let directory = try repository.meetingDirectory(for: document.meeting.id)
            let summary = try await summaryGenerator.generateSummary(for: document, meetingDirectory: directory)
            try repository.saveSummary(summary, meetingId: document.meeting.id)
            summaryMarkdown = try repository.loadSummary(meetingId: document.meeting.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Update app container injection**

Modify `MeetingTranscriptApp/App/AppContainer.swift`:

```swift
    let livePreviewTranscriber: any LivePreviewTranscribing
    let summaryGenerator: any CodexSummaryGenerating
    let markdownExporter: MarkdownTranscriptExporter
```

Update the convenience initializer:

```swift
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber(),
            summaryGenerator: CodexCLISummaryGenerator()
```

Update the designated initializer signature and assignments:

```swift
    init(
        repository: FileMeetingRepository,
        workflow: any TranscriptBuilding,
        livePreviewTranscriber: any LivePreviewTranscribing,
        summaryGenerator: any CodexSummaryGenerating
    ) {
        let markdownExporter = MarkdownTranscriptExporter()

        self.repository = repository
        self.workflow = workflow
        self.livePreviewTranscriber = livePreviewTranscriber
        self.summaryGenerator = summaryGenerator
        self.markdownExporter = markdownExporter
        self.jsonExporter = JSONTranscriptExporter()
        self.meetingListViewModel = MeetingListViewModel(repository: repository)
        self.meetingDetailViewModel = MeetingDetailViewModel(
            repository: repository,
            markdownExporter: markdownExporter,
            summaryGenerator: summaryGenerator
        )
    }
```

Update the other convenience initializers to pass `summaryGenerator: CodexCLISummaryGenerator()`.

- [ ] **Step 5: Update existing tests to pass fake summary generator**

In `MeetingDetailViewModelTests`, replace existing initializers:

```swift
let viewModel = MeetingDetailViewModel(
    repository: repository,
    markdownExporter: MarkdownTranscriptExporter(),
    summaryGenerator: FakeSummaryGenerator(mode: .success("# 摘要"))
)
```

- [ ] **Step 6: Run view model summary tests and verify they pass**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingDetailViewModelTests
```

Expected: PASS for all `MeetingDetailViewModelTests`.

- [ ] **Step 7: Commit view model summary integration**

Run:

```bash
git add MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift MeetingTranscriptApp/App/AppContainer.swift Tests/MeetingTranscriptAppTests/MeetingDetailViewModelTests.swift
git commit -m "feat: generate meeting summaries from detail view model"
```

---

### Task 4: Add Summary Button And Display To UI

**Files:**
- Modify: `MeetingTranscriptApp/UI/MeetingDetailView.swift`

- [ ] **Step 1: Add UI controls to footer**

Modify `footer(_:)` in `MeetingTranscriptApp/UI/MeetingDetailView.swift` so the button row includes:

```swift
                Button("用 Codex 整理摘要") {
                    Task {
                        await viewModel.generateSummary()
                    }
                }
                .disabled(!viewModel.canGenerateSummary || isActiveRecordingDocument(document))

                if viewModel.isGeneratingSummary {
                    ProgressView()
                        .controlSize(.small)
                    Text("Codex 整理中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

Place this after `Export Markdown` and before `Open Folder`.

- [ ] **Step 2: Add read-only summary display**

In `footer(_:)`, after the live preview warning block, add:

```swift
            if let summaryMarkdown = viewModel.summaryMarkdown, !summaryMarkdown.isEmpty {
                Divider()
                    .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Codex 摘要")
                        .font(.headline)

                    ScrollView {
                        Text(summaryMarkdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                }
            }
```

- [ ] **Step 3: Run focused build test**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingDetailViewModelTests
```

Expected: PASS and no SwiftUI compile errors in `MeetingDetailView`.

- [ ] **Step 4: Commit summary UI**

Run:

```bash
git add MeetingTranscriptApp/UI/MeetingDetailView.swift
git commit -m "feat: add codex summary action to meeting detail"
```

---

### Task 5: Document Codex Summary Behavior

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README summary description**

In `README.md`, add this paragraph after the existing transcript flow description:

```markdown
The `用 Codex 整理摘要` action sends the selected meeting's `transcript.json` content to Codex CLI through non-interactive `codex exec`. Codex returns Markdown text, and the app writes that text to `summary.md` in the meeting folder. Recording, transcription, and diarization remain local-only; the summary step uses Codex.
```

Update the meeting folder file list to include:

```markdown
- `summary.md`
```

- [ ] **Step 2: Run README grep check**

Run:

```bash
rg -n "Codex|summary.md|用 Codex 整理摘要" README.md
```

Expected: Output includes the new Codex summary paragraph, `summary.md`, and the button label.

- [ ] **Step 3: Commit documentation**

Run:

```bash
git add README.md
git commit -m "docs: document codex summary export"
```

---

### Task 6: Full Verification And App Bundle

**Files:**
- No source edits unless verification exposes a defect in this feature.

- [ ] **Step 1: Run full test suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox
```

Expected: All tests pass.

- [ ] **Step 2: Run diff whitespace check**

Run:

```bash
git diff --check
```

Expected: No output and exit code 0.

- [ ] **Step 3: Build macOS app bundle**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache SWIFT_BUILD_FLAGS=--disable-sandbox scripts/build-macos-app.sh
```

Expected: Output includes `Built app: /Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/app/MeetingTranscriptApp.app`.

- [ ] **Step 4: Manual Codex CLI smoke check**

Use the built app to open a meeting with final transcript segments, click `用 Codex 整理摘要`, and confirm:

```text
summary.md exists in the meeting folder.
The app displays the summary text.
Existing transcript.json and transcript.md are still present.
```

- [ ] **Step 5: Push branch**

Run:

```bash
git status --short --branch
git push
```

Expected: Branch `codex/meeting-transcript-app` is pushed to `https://github.com/bevan222/meeting-record.git`.
