# WhisperKit Post-Recording Transcription Design

## Goal

Replace the demo mock transcription used after Stop with real on-device WhisperKit transcription of the saved `audio.m4a`, while keeping the app local-only and leaving real-time streaming transcription for a later phase.

## Scope

This phase implements post-recording transcription only:

- Add the Argmax OSS Swift package and depend on the `WhisperKit` product from the macOS app target.
- Add a `WhisperKitTranscriptionEngine` adapter that conforms to the existing `TranscriptionEngine` port.
- Keep `MeetingTranscriptCore` free of WhisperKit imports so core models, repository, exporters, and workflow stay lightweight and testable.
- Use `WhisperKitConfig(model: "tiny")` by default for development speed.
- Keep the recording-time preview segments as a temporary UI preview.
- Continue using `MockDiarizationEngine` for this phase; SpeakerKit is the next phase.

## Architecture

`MeetingWorkflow` already depends on `TranscriptionEngine` and `DiarizationEngine`, so the integration point is the app composition layer, not the core workflow. `WhisperKitTranscriptionEngine` lives in `MeetingTranscriptApp/Services` and adapts WhisperKit results into `[TranscriptSegment]`.

The app flow remains:

```text
Record audio.m4a
-> Stop recording
-> MeetingWorkflow.buildTranscript(...)
-> WhisperKitTranscriptionEngine transcribes audio.m4a
-> MockDiarizationEngine provides speaker turns for now
-> TranscriptAssembler combines segments and speaker IDs
-> FileMeetingRepository saves transcript.json, transcript.md, metadata.json
```

## Data Mapping

WhisperKit returns transcription results with segment-level timestamps. The adapter maps each WhisperKit segment to the existing `TranscriptSegment` model:

- `id`: `seg_0001`, `seg_0002`, stable by output order
- `start`: segment start timestamp
- `end`: segment end timestamp
- `speakerId`: `nil`; diarization assignment happens later in `TranscriptAssembler`
- `text`: trimmed segment text
- `confidence`: `nil` unless WhisperKit exposes a stable confidence value in the used API

If WhisperKit returns no segment objects but does return full text, the adapter returns one segment covering `0...0` with the full text. Empty/whitespace-only output is treated as an error so the UI can show failure instead of saving an empty final transcript.

## Model And Runtime Behavior

The default model is `tiny` for first-run speed and easier debugging. WhisperKit may download model files on first use from Hugging Face through Argmax's model repository. The app remains local for inference after the model is cached, but first run can require network access for model download.

This phase does not add model selection UI. A later phase can move the model name into preferences and expose larger multilingual models.

## Error Handling

If WhisperKit initialization, model download, audio loading, or transcription fails, `MeetingListViewModel.stopRecording` keeps the recorded audio and sets `errorMessage`. The intermediate `.recorded` transcript remains without preview text, so mock preview content is not saved as final output.

## Testing

Automated tests cover the adapter's result mapping through a small mapper that does not import WhisperKit. Full WhisperKit inference is verified manually because it downloads models and depends on local hardware/runtime state.

Verification commands:

```sh
swift test
swift build
scripts/build-macos-app.sh
```

Manual acceptance:

1. Launch the app.
2. Record a short Chinese sentence.
3. Stop recording.
4. Confirm the final transcript changes from preview text to WhisperKit-produced text.
5. Confirm `transcript.json` and `transcript.md` contain the WhisperKit text.
