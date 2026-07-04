# MeetingTranscriptApp

This first slice is a local-only SwiftUI macOS app for recording a meeting, producing a transcript, assigning mock speaker labels, renaming speakers, and exporting the result. Audio and transcript files stay on the local machine under the app's Application Support directory.

The current transcription and diarization implementations are mock adapters (`MockTranscriptionEngine` and `MockDiarizationEngine`) behind the core engine ports. Real WhisperKit and SpeakerKit integrations are not wired in this slice.

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

The bundle script builds the debug executable, creates `.build/app/MeetingTranscriptApp.app`, copies the app `Info.plist`, and signs the bundle with the included entitlements.

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

`transcript.md` is written when Markdown export is requested. `transcript.json` and `metadata.json` are updated when the transcript is saved or JSON export is requested.

## Current Limitations

- WhisperKit and SpeakerKit are still represented by ports and mock adapters; real model-backed transcription and diarization are future integration work.
- `swift test` may require a full Xcode/XCTest toolchain. In this local CommandLineTools environment it can fail with `no such module 'XCTest'`, which is a toolchain limitation rather than an app-specific test failure.

## Manual MVP Checklist

- Record a short meeting from the app and confirm the meeting appears in the list.
- Open the meeting and confirm transcript segments are displayed.
- Confirm mock speaker attribution appears on transcript rows.
- Rename a speaker and confirm the new name is reflected in the transcript display and saved data.
- Use JSON export and confirm `transcript.json` is present in the meeting folder.
- Use Markdown export and confirm `transcript.md` is present in the meeting folder.
