# WhisperKit Post-Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace post-stop mock transcription with real WhisperKit local transcription of `audio.m4a`.

**Architecture:** Keep `MeetingTranscriptCore` dependency-free and add a WhisperKit adapter in the app target. The existing `MeetingWorkflow` remains the orchestration point through the `TranscriptionEngine` protocol.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI macOS, Argmax OSS Swift `WhisperKit`, XCTest.

---

## File Structure

- Modify: `Package.swift`
- Create: `MeetingTranscriptApp/Services/WhisperKitTranscriptionEngine.swift`
- Create: `MeetingTranscriptApp/Services/WhisperKitSegmentMapper.swift`
- Modify: `MeetingTranscriptApp/App/AppContainer.swift`
- Create: `Tests/MeetingTranscriptAppTests/WhisperKitSegmentMapperTests.swift`
- Modify: `README.md`

## Task 1: Add Testable Segment Mapping

- [ ] Add `WhisperKitSegmentMapperTests` that verifies ordered segments are mapped to stable `seg_0001` IDs and trimmed text.
- [ ] Implement `WhisperKitSegmentMapper` using an app-local input struct so tests do not need to instantiate WhisperKit types.
- [ ] Run `swift test`.
- [ ] Commit with `feat: add whisperkit segment mapping`.

## Task 2: Add WhisperKit Dependency And Adapter

- [ ] Add `.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")` to `Package.swift`.
- [ ] Add `.product(name: "WhisperKit", package: "argmax-oss-swift")` to the `MeetingTranscriptApp` target.
- [ ] Implement `WhisperKitTranscriptionEngine` with default model `tiny`.
- [ ] Map `transcribe(audioPath:)` output through `WhisperKitSegmentMapper`.
- [ ] Run `swift build`.
- [ ] Commit with `feat: add whisperkit transcription engine`.

## Task 3: Wire App Composition To WhisperKit

- [ ] Update `AppContainer.workflow` to use `WhisperKitTranscriptionEngine` and keep `MockDiarizationEngine`.
- [ ] Preserve the existing `MockTranscriptionEngine.sampleSegments` recording preview.
- [ ] Run `swift test`.
- [ ] Run `scripts/build-macos-app.sh`.
- [ ] Commit with `feat: use whisperkit after recording`.

## Task 4: Documentation And Final Verification

- [ ] Update `README.md` to describe the real post-recording WhisperKit path, `tiny` default model, and first-run model download caveat.
- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `scripts/build-macos-app.sh`.
- [ ] Commit with `docs: document whisperkit transcription`.
