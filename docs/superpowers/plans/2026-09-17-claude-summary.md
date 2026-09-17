# Claude Summary Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested Claude Code summary action that safely shares `summary.md` with the existing Codex action.

**Architecture:** Introduce a provider-neutral summary protocol and process runner, with concrete Codex and Claude generators. `MeetingDetailViewModel` owns one cancellable task state and routes an explicit provider to the matching generator; SwiftUI renders two mutually exclusive actions and a provider-neutral summary section.

**Tech Stack:** Swift 6, SwiftUI, Foundation `Process`, XCTest

**Spec:** `docs/superpowers/specs/2026-09-17-claude-floating-dmg-design.md`

## Global Constraints

- Keep all transcript and summary content local except what the user explicitly sends through the selected CLI.
- Use Traditional Chinese output and Markdown.
- Preserve the old `summary.md` on failure, cancellation, or stale completion.
- Do not require a live Claude account in automated tests; use fake runners or executable scripts.

---

### Task 1: Provider-Neutral Summary Execution

**Files:**
- Modify: `MeetingTranscriptApp/Services/CodexSummaryGenerating.swift`
- Modify: `MeetingTranscriptApp/App/AppContainer.swift`
- Modify: `MeetingTranscriptApp/ViewModels/MeetingDetailViewModel.swift`
- Modify: `MeetingTranscriptApp/UI/MeetingDetailView.swift`
- Modify: `Tests/MeetingTranscriptAppTests/CodexSummaryGeneratorTests.swift`
- Modify: `Tests/MeetingTranscriptAppTests/MeetingDetailViewModelTests.swift`

**Interfaces:**
- Produces: `enum SummaryProvider { case codex, claude }` with visible action/progress labels.
- Produces: `protocol SummaryGenerating` with `generateSummary(for:meetingDirectory:) async throws -> String`.
- Produces: `MeetingDetailViewModel.generateSummary(using:)`, `activeSummaryProvider`, and cancellation on `load(meetingId:)`.
- Produces: `CodexCLISummaryGenerator` and `ClaudeCLISummaryGenerator` using a shared prompt builder and cancellable process runner.

- [ ] **Step 1: Write failing generator tests**

Add tests proving Claude chooses the next existing executable, uses exactly:

```swift
["-p", "--input-format", "text", "--output-format", "text",
 "--no-session-persistence", "--tools", "", "--disallowedTools", "mcp__*"]
```

and returns trimmed stdout. Assert missing executable, non-zero exit, empty output, shared Traditional Chinese prompt, and cancellation behavior.

- [ ] **Step 2: Run the generator tests and verify failure**

Run: `swift test --filter SummaryGeneratorTests`

Expected: FAIL because the Claude generator and provider-neutral runner do not exist.

- [ ] **Step 3: Implement the provider-neutral generators**

Keep the current Codex sandbox arguments and output-file behavior. Add stdout capture for Claude without shell invocation, discover the three approved Claude paths, and preserve process cancellation. Keep provider-specific readable error text.

- [ ] **Step 4: Run generator tests**

Run: `swift test --filter SummaryGeneratorTests`

Expected: PASS.

- [ ] **Step 5: Write failing view-model tests**

Add tests that construct two fake generators and assert:

```swift
await viewModel.generateSummary(using: .claude)
XCTAssertEqual(claude.requestedDocuments.count, 1)
XCTAssertEqual(codex.requestedDocuments.count, 0)
XCTAssertNil(viewModel.activeSummaryProvider)
```

Also assert a second provider cannot start concurrently, failure/cancellation preserves the old `summary.md`, and changing meetings cancels without saving stale output.

- [ ] **Step 6: Run view-model tests and verify failure**

Run: `swift test --filter MeetingDetailViewModelTests`

Expected: FAIL because provider routing and cancellation are absent.

- [ ] **Step 7: Implement view-model, container, and UI routing**

Inject both generators in `AppContainer`. Replace the Boolean generating flag with `activeSummaryProvider`, keep `canGenerateSummary` false while either provider runs, call `Task.checkCancellation()` before saving, and treat `CancellationError` as a quiet cancellation. Add buttons `用 Codex 整理摘要` and `用 Claude 整理摘要`; disable both while one runs or during active recording. Render progress with the selected provider and rename `Codex 摘要` to `會議摘要`.

- [ ] **Step 8: Run focused and full tests**

Run: `swift test --filter MeetingDetailViewModelTests`

Run: `swift test`

Expected: all tests PASS.

- [ ] **Step 9: Commit**

```bash
git add MeetingTranscriptApp Tests/MeetingTranscriptAppTests docs/superpowers
git commit -m "feat: add Claude summary provider"
```
