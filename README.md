# MeetingTranscriptApp

This is a local-only SwiftUI macOS app for recording a meeting, producing a transcript, assigning speaker labels, renaming speakers, and exporting the result. Audio and transcript files stay on the local machine under the app's Application Support directory.

The app attempts to refresh a UI-only live preview every 10 seconds while recording. Preview text is not saved as the final transcript. After recording stops, the app transcribes the saved `audio.m4a` with WhisperKit through the `WhisperKitTranscriptionEngine` adapter, then runs SpeakerKit diarization through `SpeakerKitDiarizationEngine` and merges speaker labels onto transcript segments.

## Build

Build the Swift package:

```sh
swift build
```

## Build and Run the macOS App Bundle

Create the app bundle:

```sh
scripts/build-macos-app.sh
```

Then open it:

```sh
open .build/app/MeetingTranscriptApp.app
```

The bundle script builds the debug executable, creates `.build/app/MeetingTranscriptApp.app`, copies the app `Info.plist`, signs the bundle with the included entitlements, and verifies the signature.

## WhisperKit and SpeakerKit Runtime

The app uses the Argmax OSS Swift `WhisperKit` product and defaults to the `large-v3-v20240930_626MB` model for better Chinese transcription quality. The first real transcription may download model files through WhisperKit's model repository before inference runs locally, so the first stop/transcribe action can take longer. After the model is cached, transcription runs on device.

The app also uses the Argmax OSS Swift `SpeakerKit` product after recording stops. SpeakerKit may download Pyannote Core ML model files on first use before diarization runs locally. After diarization completes, the app assigns `Speaker 1`, `Speaker 2`, etc. by matching SpeakerKit time ranges to transcript segment timestamps.

The current flow is:

```text
Record audio.m4a -> refresh UI-only preview every 10 seconds -> Stop -> WhisperKit transcribes full audio.m4a -> SpeakerKit diarizes full audio.m4a -> save transcript.json/transcript.md
```

The `用 Codex 整理摘要` action sends the selected meeting's `transcript.json` content to Codex CLI through ephemeral non-interactive `codex exec`. Codex returns Markdown text, and the app writes that text to `summary.md` in the meeting folder. Recording, transcription, and diarization remain local-only; the summary step uses Codex.

## Runtime Storage

Meetings are saved locally in one independent directory per recording under:

```text
~/Library/Application Support/MeetingTranscriptApp/Meetings
```

Each meeting has its own directory containing:

- `audio.m4a`
- `transcript.json`
- `transcript.md`
- `summary.md`
- `metadata.json`

`transcript.json`, `transcript.md`, and `metadata.json` are updated whenever the transcript is saved. The export buttons force-save the current JSON or Markdown again.

## Current Limitations

- Recording-time transcript rows are UI-only preview content. The final transcript is produced after Stop.
- Speaker diarization runs after recording stops, not live during recording.
- There is no model picker UI yet. The default WhisperKit model is `large-v3-v20240930_626MB`.

## Manual MVP Checklist

- Record a short meeting from the app and confirm the meeting appears in the list.
- Open the meeting and confirm preview transcript segments are displayed while recording.
- Stop recording and confirm WhisperKit replaces the preview with final transcript text.
- Confirm mock speaker attribution appears on final transcript rows.
- Rename a speaker and confirm the new name is reflected in the transcript display and saved data.
- Use JSON export and confirm `transcript.json` is present in the meeting folder.
- Use Markdown export and confirm `transcript.md` is present in the meeting folder.
