# 10-Second Live Preview Transcription Design

## Goal

Add a recording-time transcript preview that attempts to update every 10 seconds using on-device WhisperKit, while keeping the final transcript generation unchanged: after Stop, the app still reprocesses the full `audio.m4a` with WhisperKit and SpeakerKit and saves that final result to `transcript.json` and `transcript.md`.

## Scope

This phase implements a pragmatic live preview, not full streaming transcription:

- Start a preview loop after recording starts.
- Attempt a preview transcription every 10 seconds.
- Show preview text in the transcript area while recording.
- Keep preview speaker attribution as unknown; speaker labels remain post-recording only.
- Do not write preview segments to the final `transcript.json` or `transcript.md`.
- Stop and clear the preview loop when recording stops or recording fails.
- Skip a preview tick if the previous preview transcription is still running.
- Preserve the current post-recording finalization flow: `transcribing -> diarizing -> 完成`.

Out of scope:

- True low-latency audio buffer streaming.
- Real-time SpeakerKit diarization.
- User-configurable preview interval UI.
- Persisting preview drafts as separate files.

## Recommended Approach

Use a 10-second periodic preview loop in the app layer. The loop asks a preview transcription service to transcribe a temporary snapshot of the currently available recording audio and then updates UI-only preview segments. If the active recording file cannot be read safely at a tick, that tick is skipped and recording continues.

This is intentionally conservative. WhisperKit inference is expensive enough that a 5-second interval can overlap work and make the UI feel unstable on lower-power Macs. A 10-second interval gives useful feedback without tripling the number of preview attempts compared with a 30-second baseline.

## Architecture

Keep `MeetingTranscriptCore` unchanged. The preview is an app concern because it is temporary UI state and should not become part of the canonical transcript model.

New app-layer pieces:

- `LivePreviewTranscribing` protocol: transcribes an in-progress recording URL into `[TranscriptSegment]`.
- `WhisperKitLivePreviewTranscriber`: production adapter that reuses the existing WhisperKit mapping and Traditional Chinese prompt behavior.
- `LiveTranscriptPreviewState`: view-model state for preview segments, activity, and a non-blocking warning message.

`MeetingListViewModel` remains responsible for recording lifecycle coordination:

```text
Start recording
-> create meeting folder and audio.m4a
-> save recording preview document shell
-> start 10-second live preview loop
-> UI shows live preview segments if present

Stop recording
-> cancel preview loop
-> clear UI-only preview state
-> finalize audio.m4a
-> run existing full-file MeetingWorkflow
-> save final transcript.json/transcript.md/metadata.json
```

## Data Flow

Preview data is intentionally separate from saved transcript data.

```text
audio.m4a while recording
-> every 10 seconds, preview service reads current audio
-> WhisperKit produces temporary segments
-> UI displays segments as "暫定逐字稿"
-> no JSON/Markdown write from preview
```

When Stop is pressed:

```text
audio.m4a final file
-> WhisperKit final transcription
-> SpeakerKit diarization
-> TranscriptAssembler speaker assignment
-> FileMeetingRepository saves final files
```

The final transcript does not merge with preview output. This avoids duplicate text, partial words, or inconsistent timestamps from live preview attempts.

## UI Behavior

While recording:

- If preview segments exist, the transcript list displays them under a lightweight `暫定逐字稿` state.
- Preview rows use the existing unknown speaker display because speaker attribution remains post-recording only.
- The user can keep recording even if preview transcription fails.
- A preview failure is shown as a small non-blocking warning, not as a recording failure.

After Stop:

- Preview rows are cleared.
- The existing processing status takes over: `轉文字中...`, then `講者標註中...`, then `完成` or `失敗`.

## Concurrency Rules

The preview loop must not allow overlapping WhisperKit calls:

- Track whether a preview transcription is in flight.
- If the next 10-second tick fires while a preview is running, skip that tick.
- Cancel the preview loop on Stop, failed recording, or app view-model teardown.
- Ignore preview results that arrive after the active recording changed.

UI updates happen on `MainActor`. WhisperKit work should run asynchronously so the main window stays responsive.

## Error Handling

Preview errors are non-fatal:

- If preview transcription fails, keep recording.
- Keep the last successful preview visible unless the recording has stopped.
- Store a short warning such as `暫定逐字稿更新失敗，停止錄音後仍會產生正式逐字稿。`
- Do not change the meeting status to `.failed` for preview-only failures.

Final transcription and diarization errors keep the current behavior: the app saves the audio, marks the meeting failed, and shows the real error message.

## Testing

Automated tests should focus on lifecycle and state behavior without running real WhisperKit:

- Starting recording starts the preview loop.
- A preview tick updates UI-only preview segments.
- Preview segments are not saved to `transcript.json`.
- A running preview prevents the next tick from starting overlapping work.
- Stopping recording cancels preview and clears preview state before final processing.
- Preview failure sets a warning but does not fail the meeting.
- Final post-recording transcript still replaces any preview content.

Manual acceptance:

1. Launch the app.
2. Start recording and speak for at least 20 seconds.
3. Confirm the first preview attempt starts after 10 seconds, with text appearing after WhisperKit finishes.
4. Stop recording.
5. Confirm preview text is replaced by the final WhisperKit + SpeakerKit transcript.
6. Confirm `transcript.json` and `transcript.md` contain only the final transcript.

## Success Criteria

- Recording-time preview uses real local WhisperKit output.
- Preview update cadence is 10 seconds.
- The app remains usable if a preview attempt is slow or fails.
- Saved transcript files remain final-only and are not polluted by draft preview text.
- Existing recording, stop, final transcription, SpeakerKit diarization, speaker rename, meeting rename, and export behavior continue to pass tests.
