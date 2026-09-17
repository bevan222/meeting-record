# Meet Note

Meet Note is a SwiftUI macOS app for recording meetings, producing transcripts, assigning and renaming speakers, exporting results, and optionally generating summaries with Codex or Claude. Recordings and transcripts are stored locally under the app's Application Support directory. Transcription and diarization run on device after their models are downloaded; optional summaries can send transcript data to an external provider.

The app attempts to refresh a UI-only live preview every 10 seconds while recording. Preview text is not saved as the final transcript. After recording stops, the app transcribes the saved `audio.m4a` with WhisperKit through the `WhisperKitTranscriptionEngine` adapter, then runs SpeakerKit diarization through `SpeakerKitDiarizationEngine` and merges speaker labels onto transcript segments.

## Install the Internal Release

- Requires an **Apple Silicon Mac (arm64), macOS 14 or later**, microphone permission, and enough storage for recordings and downloaded models. Intel Macs are not supported by this DMG.
- The release artifact is **`.build/dist/Meet Note.dmg`**. Open the DMG, drag `Meet Note.app` onto `Applications`, eject the image, then launch Meet Note from Applications.
- This internal build is **ad-hoc signed, not Developer ID signed or Apple-notarized**. A passing signature check is an integrity check, not Apple approval. Only open a copy received from a trusted internal distributor.
- On first open, try right-clicking Meet Note and choosing **Open**. If macOS still blocks it, attempt launch once, then use **System Settings > Privacy & Security > Open Anyway** and confirm. Managed Macs may require IT approval. Do not disable Gatekeeper globally. See [Apple's instructions for opening trusted apps](https://support.apple.com/en-gb/102445).

## Build

Source builds require Xcode with the macOS SDK and Swift 6 or later.

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
open ".build/app/Meet Note.app"
```

The bundle script defaults to Debug/arm64, creates `.build/app/Meet Note.app`, copies the app `Info.plist` and all top-level SwiftPM resource bundles from the selected build output, signs the bundle with the included entitlements, and verifies the signature. `BUILD_CONFIGURATION=release` selects Release. App packaging uses SwiftPM's Xcode backend so generated accessors find bundles in `Contents/Resources` through the main app bundle, without invalid app-root links or a developer-checkout fallback. Build outputs are under `.build/apple/Products/Debug` or `Release`; missing `swift-transformers_Hub.bundle` fails the build. Ordinary `swift build` and `swift test` still use their default backend.

The app is signed without macOS App Sandbox. Summary actions launch local provider CLIs using the current user's authentication and configuration.

## Build and Verify the Release DMG

```sh
scripts/build-release-dmg.sh
scripts/verify-release-dmg.sh ".build/dist/Meet Note.dmg"
```

The release builder creates a unique candidate under `.build/dist`, verifies its mounted contents, resources, metadata, architecture, deployment target, signature, and successful unmount, then atomically renames it to `.build/dist/Meet Note.dmg`. Creation or verification failure removes the candidate and preserves any previous verified final image. Run packaging builds one at a time because app assembly uses the shared `.build/app` directory.

Packaging regression checks do not run real builds or mount images:

```sh
bash scripts/test-packaging.sh
scripts/verify-release-dmg.sh --self-test
swift test --filter BrandingTests
swift test
```

After a real Release build, exercise the generated Hub resource accessor in a disposable relocated app copy:

```sh
bash scripts/test-packaged-resources.sh ".build/app/Meet Note.app"
```

The probe rejects lookup through the developer checkout and reads both bundled tokenizer configurations. It does not launch the app UI, record audio, or call a summary provider.

## Summary Provider Setup and Data Handling

Only the provider you choose needs to be installed and authenticated. Neither CLI nor provider credentials are included in the DMG.

- **Codex:** this build checks `/Applications/ChatGPT.app/Contents/Resources/codex`, then `/Applications/Codex.app/Contents/Resources/codex`. Install an approved app version containing that executable; a standalone `codex` available only on your shell's `PATH` is not discovered by this build. Run the discovered executable with `login` in Terminal under the same macOS user, and complete the authorized account sign-in. See [Codex authentication](https://developers.openai.com/codex/auth).
- **Claude:** install [Claude Code](https://code.claude.com/docs/en/setup) at `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, or `/usr/local/bin/claude`. Run that executable interactively in Terminal under the same macOS user and complete sign-in (`/login` if needed). Use an authorized account with Claude Code access; see [Claude Code authentication](https://code.claude.com/docs/en/authentication).
- A Finder-launched app may not inherit shell-only environment variables. Complete authentication before using either summary action; check CLI errors, account access, network access, and usage limits if a summary fails. Contact the internal distributor for unsupported executable locations or installation problems.
- Choosing **用 Codex 整理摘要** or **用 Claude 整理摘要** passes the selected meeting's transcript data and summary instructions to that local CLI. The CLI may send them to its provider's service using your account/configuration, with the corresponding data policies and usage charges. Local CLI execution does **not** mean the summary stays on device. Only submit meeting data approved for that provider by your organization.
- The returned Markdown is saved locally as `summary.md`. Audio recording, transcription, and diarization do not require either summary CLI.

## WhisperKit and SpeakerKit Runtime

The app uses the Argmax OSS Swift `WhisperKit` product and defaults to the `large-v3-v20240930_626MB` model for better Chinese transcription quality. The first real transcription may download model files through WhisperKit's model repository before inference runs locally, so the first stop/transcribe action can take longer. After the model is cached, transcription runs on device.

The app also uses the Argmax OSS Swift `SpeakerKit` product after recording stops. SpeakerKit may download Pyannote Core ML model files on first use before diarization runs locally. After diarization completes, the app assigns `Speaker 1`, `Speaker 2`, etc. by matching SpeakerKit time ranges to transcript segment timestamps.

The current flow is:

```text
Record audio.m4a -> refresh UI-only preview every 10 seconds -> Stop -> WhisperKit transcribes full audio.m4a -> SpeakerKit diarizes full audio.m4a -> save transcript.json/transcript.md
```

The optional Codex and Claude summary actions use the provider setup and data flow described above, separately from local transcription and diarization.

## Runtime Storage

Meetings are saved locally in one independent directory per recording. For compatibility with recordings created before the Meet Note branding update, the app continues to use its original internal storage directory:

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
