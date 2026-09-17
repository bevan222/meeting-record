# Codex Summary Export Design

## Goal

Add an in-app action that sends the current meeting transcript to the local Codex CLI, asks Codex to produce a structured meeting summary in Traditional Chinese, and saves the result as `summary.md` in the same meeting folder.

This feature intentionally keeps recording, transcription, and diarization local-only. The summary step is different: it sends transcript content through Codex CLI and should be presented in the UI as a Codex-powered action.

## Scope

Implement the first version as a single button on the meeting detail screen:

- Button label: `用 Codex 整理摘要`
- Input source: the selected meeting's `transcript.json`
- Output file: `summary.md`
- Output language: Traditional Chinese
- Output format: Markdown
- App behavior: Codex only returns text; the app writes `summary.md` itself

Do not add custom prompt editing, model selection, background scheduling, or summary history in this phase.

## User Experience

The footer on the meeting detail screen gets a new `用 Codex 整理摘要` button near the existing export buttons.

The button is enabled only when:

- A meeting is selected.
- The meeting has at least one final transcript segment.
- The app is not currently recording that selected meeting.
- A Codex summary request is not already running.

When the user clicks the button:

1. The UI shows a running state such as `Codex 整理中...`.
2. The app sends the current `transcript.json` content to Codex CLI with a fixed summary prompt.
3. On success, the app saves the Codex response to `summary.md`.
4. The UI reloads and displays the saved summary text below the transcript controls.
5. On failure, the UI shows the error and keeps the previous `summary.md`, if one exists.

## Prompt

Use a fixed prompt for the first version:

```text
請根據以下會議逐字稿整理：
1. 重點摘要
2. 決議事項
3. 待辦事項
4. 負責人
5. 期限
6. 未解問題

請使用繁體中文，輸出 Markdown。
```

The prompt should include the transcript JSON after the instructions. JSON is preferred over Markdown because it preserves meeting metadata, speaker ids, speaker names, timestamps, and segment boundaries.

## CLI Integration

Use the Codex CLI non-interactive mode:

```bash
/Applications/Codex.app/Contents/Resources/codex exec --skip-git-repo-check --output-last-message <output-file> -
```

The app should pass the prompt through stdin by using `-`. This avoids command-line length limits when a transcript is long. The app should treat Codex as a text generator, not as an agent that edits the meeting folder. Codex writes its final response to a temporary output file. The app reads that output file and writes it to `summary.md`.

Use `Process` rather than shell interpolation so transcript content and file paths are passed safely. The production runner should support an injectable executable URL for tests, but the default should point at `/Applications/Codex.app/Contents/Resources/codex`.

The command should run with the selected meeting directory as its working directory. It should use `--skip-git-repo-check` because meeting folders are not git repositories.

## Components

### `CodexSummaryGenerating`

An app-layer protocol that accepts a `TranscriptDocument` and meeting directory URL, then returns Markdown summary text.

This keeps UI and view models testable without launching Codex CLI.

### `CodexCLISummaryGenerator`

Production implementation backed by `Process`.

Responsibilities:

- Build the fixed Traditional Chinese Markdown prompt.
- Encode the current `TranscriptDocument` as transcript JSON for the prompt body.
- Run `codex exec` non-interactively.
- Capture stderr for useful failure messages.
- Read the `--output-last-message` file on success.
- Reject empty summary output.
- Clean up temporary output files.

### `FileMeetingRepository`

Add focused summary helpers:

- `saveSummary(_ summary: String, meetingId: String)`
- `loadSummary(meetingId: String) -> String?`

`summary.md` remains derived output and does not change the canonical `transcript.json` schema.

### `MeetingDetailViewModel`

Add published state:

- `summaryMarkdown: String?`
- `isGeneratingSummary: Bool`

Add action:

- `generateSummary() async`

The action should:

1. Save the latest transcript first, so Codex sees current title, speaker names, and segment edits.
2. Call the injected `CodexSummaryGenerating`.
3. Save `summary.md` through the repository.
4. Publish the loaded summary text.
5. Keep errors in `errorMessage`.

### `MeetingDetailView`

Add:

- A `用 Codex 整理摘要` button.
- A small running indicator while Codex is active.
- A summary display section when `summaryMarkdown` exists.

The summary display should be read-only selectable text in this phase. Rich Markdown rendering is out of scope for this spec.

## Data Flow

```text
Selected TranscriptDocument
-> MeetingDetailViewModel saves current transcript
-> FileMeetingRepository resolves meeting folder
-> CodexCLISummaryGenerator builds prompt with transcript.json content
-> codex exec writes final message to a temp file
-> App reads temp output
-> FileMeetingRepository writes summary.md
-> MeetingDetailViewModel publishes summaryMarkdown
-> MeetingDetailView displays the summary
```

## Error Handling

Handle these cases explicitly:

- Codex executable is missing: show a clear install/path error.
- Codex exits non-zero: show stderr when available.
- Codex returns empty output: show a clear empty-summary error.
- `summary.md` cannot be written: show the filesystem error.
- A second click happens while one request is running: ignore it by disabling the button.

Existing transcript and audio files must not be modified if summary generation fails, except for saving the current transcript before calling Codex.

## Tests

Add unit tests around the app-layer behavior:

- Summary prompt includes Traditional Chinese instructions and encoded transcript JSON.
- `MeetingDetailViewModel.generateSummary()` saves `summary.md` and publishes the result.
- Summary generation failure sets `errorMessage` and does not overwrite an existing summary.
- The action refuses to start when there are no transcript segments.
- `FileMeetingRepository` saves and loads `summary.md`.

Avoid running the real Codex CLI in tests. Use a fake `CodexSummaryGenerating` implementation.

## Manual Verification

1. Record or open a meeting with final transcript segments.
2. Confirm `用 Codex 整理摘要` is enabled after final transcription finishes.
3. Click it and confirm a running state appears.
4. Confirm `summary.md` is created in the meeting folder.
5. Confirm the summary text appears in the app.
6. Rename a speaker or edit a segment, run summary again, and confirm the updated transcript content is used.

## Success Criteria

- One click creates or refreshes `summary.md` for the selected meeting.
- Codex CLI is called non-interactively.
- Codex cannot directly edit the meeting folder; the app writes summary output.
- Existing JSON, Markdown transcript export, audio recording, WhisperKit transcription, SpeakerKit diarization, speaker rename, and live preview behavior continue to pass tests.
