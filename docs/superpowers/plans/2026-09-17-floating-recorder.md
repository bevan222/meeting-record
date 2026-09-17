# Floating Recorder Reminder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a reusable always-on-top recording reminder when the main window is minimized, with safe stop and restore actions.

**Architecture:** A testable main-actor controller receives recorder snapshots and main-window minimized state, while an AppKit presenter owns one `NSPanel`. A root `NSViewRepresentable` reports the SwiftUI main window without taking over its delegate. The existing meeting view model gains an idempotent stop guard.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, XCTest

**Spec:** `docs/superpowers/specs/2026-09-17-claude-floating-dmg-design.md`

## Global Constraints

- Show only while an active recording exists and the main window is minimized.
- Use the active recording meeting title, not the currently selected meeting title.
- Reuse the existing full stop workflow and ignore duplicate stop requests.
- Do not replace SwiftUI's window delegate or create a new panel per minimize event.

---

### Task 1: Idempotent Stop Request

**Files:**
- Modify: `MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift`
- Modify: `Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift`

**Interfaces:**
- Produces: `stopRecording(container:)` accepts at most one active stop workflow until it completes.
- Produces: `activeRecordingTitle: String?` resolved from `activeRecordingMeetingId` and `meetings`.

- [ ] **Step 1: Write the failing tests**

Add a recorder fake that counts `stopRecording()` calls and suspends completion. Start recording, invoke `viewModel.stopRecording(container:)` twice, and assert the recorder count is `1`. Add a test proving `activeRecordingTitle` remains tied to the recording meeting after selection changes.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter MeetingListViewModelTests`

Expected: duplicate stop test FAILS with two accepted workflows or an erroneous failure transition.

- [ ] **Step 3: Add the minimal stop guard and title projection**

Use a main-actor Boolean or task identity that is set synchronously before spawning the stop task and cleared only after the stop workflow finishes. Keep all existing finalization and failure handling intact.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter MeetingListViewModelTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MeetingTranscriptApp/ViewModels/MeetingListViewModel.swift Tests/MeetingTranscriptAppTests/MeetingListViewModelTests.swift
git commit -m "fix: guard duplicate recording stops"
```

### Task 2: Floating Panel Controller and App Integration

**Files:**
- Create: `MeetingTranscriptApp/UI/RecordingFloatingPanel.swift`
- Modify: `MeetingTranscriptApp/App/MeetingTranscriptApp.swift`
- Create: `Tests/MeetingTranscriptAppTests/RecordingFloatingPanelControllerTests.swift`

**Interfaces:**
- Consumes: `MeetingListViewModel.activeRecordingTitle`, recorder `.state`, and `elapsedSeconds`.
- Produces: `FloatingRecorderSnapshot`, a presenter protocol, a main-window protocol, and `RecordingFloatingPanelController`.
- Produces: `MainWindowAccessor` that attaches only the root Meet Note window.

- [ ] **Step 1: Write failing controller tests**

Use fake presenter and fake main window to assert the visibility table: only `.recording + minimized + snapshot` shows. Assert subsequent title/time changes update the same presenter; `.stopping`, `.failed`, missing snapshot, deminiaturize, and detach hide. Assert restore calls deminiaturize/front/activate behavior through the window abstraction, while stop invokes its closure once.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter RecordingFloatingPanelControllerTests`

Expected: FAIL because controller types do not exist.

- [ ] **Step 3: Implement the controller and reusable panel**

Create one borderless or titled utility `NSPanel` with stable compact dimensions. Set:

```swift
panel.level = .floating
panel.hidesOnDeactivate = false
panel.isReleasedWhenClosed = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

Render a red indicator, title, monospaced elapsed time, `stop.fill`, and `macwindow` buttons with tooltips. Observe only `didMiniaturize`, `didDeminiaturize`, and `willClose` for the attached main window, and remove old tokens on reattach/detach.

- [ ] **Step 4: Integrate at the App root**

Have `MeetingTranscriptApplication` strongly own the controller and pass the real stop closure to `MeetingListViewModel.stopRecording(container:)`. Feed recorder/list updates to the controller and use `MainWindowAccessor` in the root view. Do not show the panel merely because the app loses focus.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter RecordingFloatingPanelControllerTests`

Run: `swift test`

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add MeetingTranscriptApp/App MeetingTranscriptApp/UI Tests/MeetingTranscriptAppTests docs/superpowers
git commit -m "feat: show floating recording reminder"
```
