# 10-Second Live Preview Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 10-second recording-time WhisperKit preview that updates the UI without writing draft preview content to final transcript files.

**Architecture:** Keep `MeetingTranscriptCore` unchanged. Add app-layer preview state, a preview transcription protocol, and a production transcriber that snapshots the active recording file before running WhisperKit. `MeetingListViewModel` owns the preview loop lifecycle; `MeetingDetailView` renders preview segments only while recording.

**Tech Stack:** Swift 6, SwiftUI macOS, XCTest, AVFoundation `AVAudioRecorder`, Argmax OSS Swift `WhisperKit`.

---

## File Structure

- Create `MeetingTranscriptApp/Services/LivePreviewTranscribing.swift`
  - Defines `LivePreviewTranscribing`.
  - Defines `WhisperKitLivePreviewTranscriber`.
  - Copies the active audio file to a temporary snapshot before invoking the existing `WhisperKitTranscriptionEngine`.
- Modify `MeetingTranscriptApp/App/AppContainer.swift`
  - Adds `livePreviewTranscriber` dependency injection.
  - Production uses `WhisperKitLivePreviewTranscriber(transcriptionEngine: WhisperKitTranscriptionEngine())`.
- Modify `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`
  - Adds UI-only preview state.
  - Starts and stops the 10-second loop.
  - Adds a testable `runLivePreviewTick(container:)` method.
  - Removes saved mock preview segments from the recording placeholder document.
- Modify `MeetingTranscriptApp/UI/ContentView.swift`
  - Passes preview state from list view model into detail view.
- Modify `MeetingTranscriptApp/UI/MeetingDetailView.swift`
  - Shows `暫定逐字稿` rows while recording when preview segments exist.
  - Shows preview warnings without blocking recording.
  - Keeps final transcript rendering unchanged after recording stops.
- Modify `Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift`
  - Adds fake preview transcribers.
  - Covers preview update, no JSON persistence, non-overlap, failure warning, cancellation, and final transcript replacement.
- Modify `README.md`
  - Updates the runtime flow and limitation text from mock recording preview to 10-second live preview.

## Constraints And Assumptions

- The first version snapshots the currently written `audio.m4a`; if `AVAudioRecorder` has not produced a decodable partial file yet, that preview tick is skipped or surfaces a non-fatal warning.
- The final transcript remains authoritative. Preview segments are never merged into final output.
- The preview interval is fixed at 10 seconds for this phase.
- Real-time speaker diarization remains out of scope.

## Verification Commands

Use these commands from the repo root:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache SWIFT_BUILD_FLAGS=--disable-sandbox scripts/build-macos-app.sh
git diff --check
```

---

### Task 1: Add Preview Transcriber Dependency

**Files:**
- Create: `MeetingTranscriptApp/Services/LivePreviewTranscribing.swift`
- Modify: `MeetingTranscriptApp/App/AppContainer.swift`
- Test: compile through `MeetingListViewModelTests`

- [ ] **Step 1: Create the preview protocol and production snapshot transcriber**

Create `MeetingTranscriptApp/Services/LivePreviewTranscribing.swift`:

```swift
import Foundation
import MeetingTranscriptCore

protocol LivePreviewTranscribing: Sendable {
    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment]
}

struct WhisperKitLivePreviewTranscriber: LivePreviewTranscribing {
    private let transcriptionEngine: any TranscriptionEngine

    init(transcriptionEngine: any TranscriptionEngine = WhisperKitTranscriptionEngine()) {
        self.transcriptionEngine = transcriptionEngine
    }

    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension)

        try FileManager.default.copyItem(at: audioURL, to: snapshotURL)
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        return try await transcriptionEngine.transcribe(
            audioURL: snapshotURL,
            options: TranscriptionOptions(language: language)
        )
    }
}
```

- [ ] **Step 2: Inject the preview transcriber in AppContainer**

Modify `MeetingTranscriptApp/App/AppContainer.swift`:

```swift
@MainActor
final class AppContainer: ObservableObject {
    let repository: FileMeetingRepository
    let workflow: any TranscriptBuilding
    let livePreviewTranscriber: any LivePreviewTranscribing
    let markdownExporter: MarkdownTranscriptExporter
    let jsonExporter: JSONTranscriptExporter

    let meetingListViewModel: MeetingListViewModel
    let meetingDetailViewModel: MeetingDetailViewModel

    convenience init() {
        self.init(
            repository: FileMeetingRepository(rootDirectory: AppDirectories.meetingsDirectory()),
            workflow: MeetingWorkflow(
                transcriptionEngine: WhisperKitTranscriptionEngine(),
                diarizationEngine: SpeakerKitDiarizationEngine(),
                assembler: TranscriptAssembler()
            ),
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber()
        )
    }

    init(
        repository: FileMeetingRepository,
        workflow: any TranscriptBuilding,
        livePreviewTranscriber: any LivePreviewTranscribing
    ) {
        let markdownExporter = MarkdownTranscriptExporter()

        self.repository = repository
        self.workflow = workflow
        self.livePreviewTranscriber = livePreviewTranscriber
        self.markdownExporter = markdownExporter
        self.jsonExporter = JSONTranscriptExporter()
        self.meetingListViewModel = MeetingListViewModel(repository: repository)
        self.meetingDetailViewModel = MeetingDetailViewModel(repository: repository, markdownExporter: markdownExporter)
    }

    convenience init(repository: FileMeetingRepository, workflow: any TranscriptBuilding) {
        self.init(
            repository: repository,
            workflow: workflow,
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber()
        )
    }

    convenience init(repository: FileMeetingRepository) {
        self.init(
            repository: repository,
            workflow: MeetingWorkflow(
                transcriptionEngine: WhisperKitTranscriptionEngine(),
                diarizationEngine: SpeakerKitDiarizationEngine(),
                assembler: TranscriptAssembler()
            ),
            livePreviewTranscriber: WhisperKitLivePreviewTranscriber()
        )
    }
}
```

- [ ] **Step 3: Run compile-focused tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests/testStopSuccessPersistsInjectedWorkflowTranscript
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add MeetingTranscriptApp/Services/LivePreviewTranscribing.swift MeetingTranscriptApp/App/AppContainer.swift
git commit -m "feat: add live preview transcriber dependency"
```

---

### Task 2: Add ViewModel Preview State And Tick Tests

**Files:**
- Modify: `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`
- Modify: `Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift`

- [ ] **Step 1: Write failing tests for preview tick behavior**

Add these tests to `MeetingListViewModelTests`:

```swift
func testLivePreviewTickUpdatesUiOnlyPreviewSegmentsWithoutSavingTranscript() async throws {
    let root = try Self.makeTemporaryRoot()
    let repository = FileMeetingRepository(rootDirectory: root)
    let previewTranscriber = SucceedingLivePreviewTranscriber()
    let container = AppContainer(
        repository: repository,
        workflow: SucceedingWorkflow(),
        livePreviewTranscriber: previewTranscriber
    )
    let recorder = SuccessfulRecorder()
    let viewModel = container.meetingListViewModel
    viewModel.recorder = recorder

    viewModel.startRecording(container: container)
    let recordingDocument = try await waitForTranscript(in: repository) { document in
        document.meeting.status == .recording
    }

    await viewModel.runLivePreviewTick(container: container)

    XCTAssertEqual(viewModel.livePreviewSegments.map(\.text), ["暫定逐字稿"])
    XCTAssertNil(viewModel.livePreviewWarning)

    let savedDocument = try repository.loadTranscript(meetingId: recordingDocument.meeting.id)
    XCTAssertEqual(savedDocument.segments, [])
    XCTAssertEqual(previewTranscriber.requestedAudioURLs.map(\.lastPathComponent), ["audio.m4a"])
}

func testLivePreviewFailureSetsWarningWithoutFailingMeeting() async throws {
    let root = try Self.makeTemporaryRoot()
    let repository = FileMeetingRepository(rootDirectory: root)
    let container = AppContainer(
        repository: repository,
        workflow: SucceedingWorkflow(),
        livePreviewTranscriber: FailingLivePreviewTranscriber()
    )
    let recorder = SuccessfulRecorder()
    let viewModel = container.meetingListViewModel
    viewModel.recorder = recorder

    viewModel.startRecording(container: container)
    let recordingDocument = try await waitForTranscript(in: repository) { document in
        document.meeting.status == .recording
    }

    await viewModel.runLivePreviewTick(container: container)

    XCTAssertEqual(viewModel.livePreviewSegments, [])
    XCTAssertEqual(viewModel.livePreviewWarning, "暫定逐字稿更新失敗，停止錄音後仍會產生正式逐字稿。")
    XCTAssertEqual(try repository.loadTranscript(meetingId: recordingDocument.meeting.id).meeting.status, .recording)
}

func testLivePreviewSkipsOverlappingTick() async throws {
    let root = try Self.makeTemporaryRoot()
    let repository = FileMeetingRepository(rootDirectory: root)
    let previewTranscriber = BlockingLivePreviewTranscriber()
    let container = AppContainer(
        repository: repository,
        workflow: SucceedingWorkflow(),
        livePreviewTranscriber: previewTranscriber
    )
    let recorder = SuccessfulRecorder()
    let viewModel = container.meetingListViewModel
    viewModel.recorder = recorder

    viewModel.startRecording(container: container)
    _ = try await waitForTranscript(in: repository) { document in
        document.meeting.status == .recording
    }

    let firstTick = Task { await viewModel.runLivePreviewTick(container: container) }
    try await Task.sleep(nanoseconds: 40_000_000)
    await viewModel.runLivePreviewTick(container: container)

    XCTAssertEqual(previewTranscriber.startedCount, 1)

    previewTranscriber.complete()
    await firstTick.value
    XCTAssertEqual(viewModel.livePreviewSegments.map(\.text), ["解除阻塞後的暫定逐字稿"])
}
```

Add these test doubles near existing fake workflow types:

```swift
private final class SucceedingLivePreviewTranscriber: LivePreviewTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var audioURLs: [URL] = []

    var requestedAudioURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return audioURLs
    }

    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        lock.lock()
        audioURLs.append(audioURL)
        lock.unlock()

        return [TranscriptSegment(id: "preview_0001", start: 0, end: 3, speakerId: nil, text: "暫定逐字稿", confidence: nil)]
    }
}

private struct FailingLivePreviewTranscriber: LivePreviewTranscribing {
    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        throw Failure()
    }

    private struct Failure: Error {}
}

private final class BlockingLivePreviewTranscriber: LivePreviewTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var isComplete = false
    private var count = 0

    var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func transcribePreview(audioURL: URL, language: String) async throws -> [TranscriptSegment] {
        lock.lock()
        count += 1
        lock.unlock()

        while !completed {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        return [TranscriptSegment(id: "preview_0001", start: 0, end: 3, speakerId: nil, text: "解除阻塞後的暫定逐字稿", confidence: nil)]
    }

    func complete() {
        lock.lock()
        isComplete = true
        lock.unlock()
    }

    private var completed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isComplete
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests/testLivePreview
```

Expected: FAIL because `livePreviewSegments`, `livePreviewWarning`, and `runLivePreviewTick(container:)` do not exist.

- [ ] **Step 3: Add minimal preview state and tick implementation**

Modify `MeetingListViewModel`:

```swift
@Published var livePreviewSegments: [TranscriptSegment] = []
@Published var livePreviewWarning: String?
@Published var isLivePreviewUpdating = false

private var livePreviewTask: Task<Void, Never>?
private var isLivePreviewTranscribing = false
```

Add these methods:

```swift
func runLivePreviewTick(container: AppContainer) async {
    guard let recordingContext = activeRecordingContext else { return }
    guard !isLivePreviewTranscribing else { return }

    isLivePreviewTranscribing = true
    isLivePreviewUpdating = true
    defer {
        isLivePreviewTranscribing = false
        isLivePreviewUpdating = false
    }

    do {
        let segments = try await container.livePreviewTranscriber.transcribePreview(
            audioURL: recordingContext.audioURL,
            language: recordingContext.language
        )

        guard activeRecordingContext?.meetingId == recordingContext.meetingId else { return }
        livePreviewSegments = segments
        livePreviewWarning = nil
    } catch {
        guard activeRecordingContext?.meetingId == recordingContext.meetingId else { return }
        livePreviewWarning = "暫定逐字稿更新失敗，停止錄音後仍會產生正式逐字稿。"
    }
}

private func clearLivePreview() {
    livePreviewTask?.cancel()
    livePreviewTask = nil
    isLivePreviewTranscribing = false
    isLivePreviewUpdating = false
    livePreviewSegments = []
    livePreviewWarning = nil
}
```

Change `recordingPreviewDocument(for:)` so it saves no draft segments:

```swift
speakers: [],
segments: []
```

Update `testStopFailurePersistsFailedDocumentAndAllowsNewRecording`:

```swift
XCTAssertEqual(recordingDocument.segments, [])
```

- [ ] **Step 4: Run preview tick tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests/testLivePreview
```

Expected: PASS.

- [ ] **Step 5: Run all MeetingListViewModelTests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift
git commit -m "feat: add live preview state"
```

---

### Task 3: Start And Stop The 10-Second Preview Loop

**Files:**
- Modify: `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`
- Modify: `Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift`

- [ ] **Step 1: Write lifecycle tests**

Add tests:

```swift
func testStartRecordingBeginsLivePreviewLoop() async throws {
    let root = try Self.makeTemporaryRoot()
    let repository = FileMeetingRepository(rootDirectory: root)
    let previewTranscriber = SucceedingLivePreviewTranscriber()
    let container = AppContainer(
        repository: repository,
        workflow: SucceedingWorkflow(),
        livePreviewTranscriber: previewTranscriber
    )
    let recorder = SuccessfulRecorder()
    let viewModel = container.meetingListViewModel
    viewModel.recorder = recorder

    viewModel.startRecording(container: container)
    _ = try await waitForTranscript(in: repository) { document in
        document.meeting.status == .recording
    }

    XCTAssertTrue(viewModel.isLivePreviewLoopActive)
}

func testStopRecordingClearsLivePreviewBeforeFinalProcessing() async throws {
    let root = try Self.makeTemporaryRoot()
    let repository = FileMeetingRepository(rootDirectory: root)
    let container = AppContainer(
        repository: repository,
        workflow: SucceedingWorkflow(),
        livePreviewTranscriber: SucceedingLivePreviewTranscriber()
    )
    let recorder = SuccessfulRecorder()
    let viewModel = container.meetingListViewModel
    viewModel.recorder = recorder

    viewModel.startRecording(container: container)
    let recordingDocument = try await waitForTranscript(in: repository) { document in
        document.meeting.status == .recording
    }
    await viewModel.runLivePreviewTick(container: container)
    XCTAssertFalse(viewModel.livePreviewSegments.isEmpty)

    viewModel.stopRecording(container: container)
    _ = try await waitForTranscript(in: repository) { document in
        document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
    }

    XCTAssertEqual(viewModel.livePreviewSegments, [])
    XCTAssertNil(viewModel.livePreviewWarning)
    XCTAssertFalse(viewModel.isLivePreviewLoopActive)
}
```

- [ ] **Step 2: Run lifecycle tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests/testStartRecordingBeginsLivePreviewLoop --filter MeetingListViewModelTests/testStopRecordingClearsLivePreviewBeforeFinalProcessing
```

Expected: FAIL because `isLivePreviewLoopActive` and loop lifecycle calls do not exist.

- [ ] **Step 3: Implement the loop lifecycle**

Add to `MeetingListViewModel`:

```swift
var isLivePreviewLoopActive: Bool {
    livePreviewTask != nil
}

private func startLivePreviewLoop(container: AppContainer) {
    livePreviewTask?.cancel()
    livePreviewTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.runLivePreviewTick(container: container)
        }
    }
}
```

Call it after recording successfully starts:

```swift
activeRecordingContext = recordingContext
try repository.save(recordingPreviewDocument(for: recordingContext))
selectedMeetingId = recordingContext.meetingId
reload()
container.meetingDetailViewModel.load(meetingId: recordingContext.meetingId)
startLivePreviewLoop(container: container)
```

Call `clearLivePreview()` before stop processing:

```swift
Task { @MainActor in
    clearLivePreview()
    guard let audioURL = await recorder.stopRecording() else {
        ...
    }
```

Call `clearLivePreview()` in `markActiveRecordingFailed(...)` before setting `activeRecordingContext = nil`.

- [ ] **Step 4: Run lifecycle tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests/testStartRecordingBeginsLivePreviewLoop --filter MeetingListViewModelTests/testStopRecordingClearsLivePreviewBeforeFinalProcessing
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift
git commit -m "feat: run live preview loop while recording"
```

---

### Task 4: Render Live Preview In The Detail UI

**Files:**
- Modify: `MeetingTranscriptApp/UI/ContentView.swift`
- Modify: `MeetingTranscriptApp/UI/MeetingDetailView.swift`
- Test: `swift test` compile and manual visual check

- [ ] **Step 1: Pass preview state from ContentView**

Modify `MeetingDetailView` initializer properties:

```swift
let livePreviewSegments: [TranscriptSegment]
let livePreviewWarning: String?
let isLivePreviewUpdating: Bool
```

Update `ContentView` call site:

```swift
MeetingDetailView(
    viewModel: detailViewModel,
    recorder: listViewModel.recorder,
    canStartRecording: listViewModel.canStartRecording,
    livePreviewSegments: listViewModel.livePreviewSegments,
    livePreviewWarning: listViewModel.livePreviewWarning,
    isLivePreviewUpdating: listViewModel.isLivePreviewUpdating,
    onRecord: { listViewModel.startRecording(container: container) },
    onStop: { listViewModel.stopRecording(container: container) },
    onMeetingMetadataChanged: { listViewModel.reload() }
)
```

- [ ] **Step 2: Render preview segments only during recording**

In `MeetingDetailView`, compute displayed segments:

```swift
private var shouldShowLivePreview: Bool {
    recorder.isRecording && !livePreviewSegments.isEmpty
}
```

Replace the list block:

```swift
if shouldShowLivePreview {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 6) {
            Text("暫定逐字稿")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isLivePreviewUpdating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)

        List(livePreviewSegments) { segment in
            TranscriptSegmentRow(
                segment: segment,
                speakerName: "Unknown Speaker",
                onTextChanged: { _ in }
            )
        }
    }
} else {
    List(document.segments) { segment in
        TranscriptSegmentRow(
            segment: segment,
            speakerName: speakerName(for: segment, in: document),
            onTextChanged: { text in
                viewModel.updateSegmentText(segmentId: segment.id, text: text)
            }
        )
    }
}
```

Show warning near footer:

```swift
if let livePreviewWarning {
    Text(livePreviewWarning)
        .font(.caption)
        .foregroundStyle(.orange)
}
```

- [ ] **Step 3: Compile UI**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingProcessingStateDisplayTests
```

Expected: PASS. This primarily verifies app target compilation.

- [ ] **Step 4: Commit**

```bash
git add MeetingTranscriptApp/UI/ContentView.swift MeetingTranscriptApp/UI/MeetingDetailView.swift
git commit -m "feat: show live preview transcript"
```

---

### Task 5: Ensure Final Transcript Replaces Preview And Docs Match

**Files:**
- Modify: `Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Add final replacement assertion**

Update `testStopSuccessPersistsInjectedWorkflowTranscript`:

```swift
await viewModel.runLivePreviewTick(container: container)
XCTAssertEqual(viewModel.livePreviewSegments.map(\.text), ["暫定逐字稿"])

viewModel.stopRecording(container: container)
let completedDocument = try await waitForTranscript(in: repository) { document in
    document.meeting.id == recordingDocument.meeting.id && document.meeting.status == .speakerAttributed
}

XCTAssertEqual(viewModel.livePreviewSegments, [])
XCTAssertEqual(completedDocument.segments.map(\.text), ["真實 WhisperKit 逐字稿"])
```

If this test uses an app container without a preview transcriber, change it to:

```swift
let container = AppContainer(
    repository: repository,
    workflow: SucceedingWorkflow(),
    livePreviewTranscriber: SucceedingLivePreviewTranscriber()
)
```

- [ ] **Step 2: Update README runtime flow**

Replace the current post-recording-only flow with:

```markdown
The app attempts a 10-second live preview while recording. Preview text is UI-only and is not saved as the final transcript. After recording stops, the app transcribes the saved `audio.m4a` with WhisperKit through the `WhisperKitTranscriptionEngine` adapter, then runs SpeakerKit diarization through `SpeakerKitDiarizationEngine` and merges speaker labels onto transcript segments.
```

Update current flow:

```text
Record audio.m4a -> 10-second UI preview attempts -> Stop -> WhisperKit transcribes full audio.m4a -> SpeakerKit diarizes full audio.m4a -> save transcript.json/transcript.md
```

Update limitations:

```markdown
- Recording-time transcript rows are UI-only preview content. The final transcript is produced after Stop.
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox --filter MeetingListViewModelTests/testStopSuccessPersistsInjectedWorkflowTranscript
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift README.md
git commit -m "test: verify preview clears before final transcript"
```

---

### Task 6: Full Verification And App Bundle

**Files:**
- No code changes unless verification exposes a bug.

- [ ] **Step 1: Run full tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache swift test --disable-sandbox
```

Expected: all tests pass.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: Build the macOS app bundle**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/clang-module-cache SWIFT_BUILD_FLAGS=--disable-sandbox scripts/build-macos-app.sh
```

Expected: output ends with:

```text
Built app: /Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/app/MeetingTranscriptApp.app
```

- [ ] **Step 4: Manual verification**

Open the app:

```bash
open -a /Users/bevan/Documents/會議逐字稿app/.worktrees/codex/meeting-transcript-app/.build/app/MeetingTranscriptApp.app
```

Manual check:

1. Start a recording.
2. Speak continuously for at least 25 seconds.
3. Confirm the app attempts preview updates while recording.
4. If the partial `audio.m4a` cannot be decoded before Stop, confirm the warning is non-fatal and recording continues.
5. Stop recording.
6. Confirm final transcript replaces preview state.
7. Confirm `transcript.json` and `transcript.md` contain only final transcript text.

- [ ] **Step 5: Push branch**

Run:

```bash
git push
```

Expected: branch `codex/meeting-transcript-app` updates on `https://github.com/bevan222/meeting-record.git`.
