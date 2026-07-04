# MeetingTranscriptApp

This is a local-only SwiftUI macOS app for recording a meeting, producing a transcript, assigning speaker labels, renaming speakers, and exporting the result. Audio and transcript files stay on the local machine under the app's Application Support directory.

After recording stops, the app transcribes the saved `audio.m4a` with WhisperKit through the `WhisperKitTranscriptionEngine` adapter. During recording, the app still shows mock preview segments so the UI is not empty before the final post-recording transcript is ready. Speaker diarization is still backed by `MockDiarizationEngine`; real SpeakerKit integration is the next phase.

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

## WhisperKit Runtime

The app uses the Argmax OSS Swift `WhisperKit` product and defaults to the `tiny` model for development speed. The first real transcription may download model files through WhisperKit's model repository before inference runs locally. After the model is cached, transcription runs on device.

The current flow is post-recording:

```text
Record audio.m4a -> Stop -> WhisperKit transcribes audio.m4a -> save transcript.json/transcript.md
```

## Runtime Storage

Meetings are saved locally in:

```text
~/Library/Application Support/MeetingTranscriptApp/Meetings
```

Each meeting has its own directory containing:

- `audio.m4a`
- `transcript.json`
- `transcript.md`
- `metadata.json`

`transcript.json`, `transcript.md`, and `metadata.json` are updated whenever the transcript is saved. The export buttons force-save the current JSON or Markdown again.

## Current Limitations

- Recording-time transcript rows are preview content. The final transcript is produced after Stop.
- SpeakerKit is not wired yet; speaker labels still come from `MockDiarizationEngine`.
- There is no model picker UI yet. The default WhisperKit model is `tiny`.

## Manual MVP Checklist

- Record a short meeting from the app and confirm the meeting appears in the list.
- Open the meeting and confirm preview transcript segments are displayed while recording.
- Stop recording and confirm WhisperKit replaces the preview with final transcript text.
- Confirm mock speaker attribution appears on final transcript rows.
- Rename a speaker and confirm the new name is reflected in the transcript display and saved data.
- Use JSON export and confirm `transcript.json` is present in the meeting folder.
- Use Markdown export and confirm `transcript.md` is present in the meeting folder.
