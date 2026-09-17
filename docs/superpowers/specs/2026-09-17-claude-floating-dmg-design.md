# Meet Note Claude, Floating Recorder, and DMG Design

## Scope

This release adds three independently testable capabilities:

1. A Claude Code summary action beside the existing Codex action.
2. An always-on-top recording reminder shown only while the main window is minimized and recording is active.
3. An internal-test DMG containing `Meet Note.app` and an Applications shortcut.

## Summary Providers

- Codex and Claude use the same Traditional Chinese, Markdown-only prompt and the current transcript JSON.
- Each provider has its own executable discovery and CLI arguments.
- Claude candidates include `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, and `/usr/local/bin/claude`.
- Claude runs with `-p --input-format text --output-format text --no-session-persistence --tools "" --disallowedTools "mcp__*"`.
- The two actions cannot run concurrently. The UI identifies the active provider.
- A successful provider overwrites the meeting's single `summary.md`; failure or cancellation preserves the existing file.
- Changing meetings cancels the active request, and a cancelled or stale request must not save or publish output.
- The visible summary heading is provider-neutral: `會議摘要`.

## Floating Recorder

- Show one reusable `NSPanel` only when the main Meet Note window is minimized, the recorder state is `.recording`, and an active recording meeting exists.
- The panel shows a red recording indicator, the active recording meeting title, elapsed time, a stop icon button, and a return-to-main-window icon button.
- The panel is floating, remains visible when Meet Note is inactive, can join all Spaces, and can appear beside full-screen apps.
- Restoring the main window, stopping, a recorder failure, or losing the active recording context hides the panel.
- Switching apps without minimizing must not show it.
- Stop uses `MeetingListViewModel.stopRecording(container:)`, preserving the existing save/transcribe/diarize workflow.
- Duplicate stop requests are ignored at the view-model boundary.
- The app observes window notifications without replacing SwiftUI's window delegate.

## Internal DMG

- Build a Release app for Apple Silicon with macOS 14 as the minimum deployment target.
- Preserve the visible product name `Meet Note` and the existing storage directory for compatibility.
- Add bundle version `1.0.0` and build number `1`.
- Ad-hoc sign and verify the app, then create `.build/dist/Meet Note.dmg`.
- The DMG contains `Meet Note.app`, an `Applications` symlink, and a short Traditional Chinese installation note explaining first-launch right-click Open.
- This is not notarized because no Apple Developer signing identity is available.
