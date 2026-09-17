# Internal DMG Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce one verified internal-test `Meet Note.dmg` containing the Release app and installation guidance.

**Architecture:** Generalize the existing app bundling script to accept Debug or Release configuration without duplicating bundle assembly. A second script creates a clean DMG staging directory, adds the app, Applications symlink, and installation note, then builds a compressed disk image with `hdiutil`.

**Tech Stack:** SwiftPM, Bash, `actool`, `codesign`, `hdiutil`, XCTest

**Spec:** `docs/superpowers/specs/2026-09-17-claude-floating-dmg-design.md`

## Global Constraints

- Output exactly `.build/dist/Meet Note.dmg`.
- Use Release configuration, Apple Silicon, macOS 14 minimum, and ad-hoc signing.
- Do not claim notarization or Gatekeeper-clean installation.
- Preserve `Meet Note` visible naming and `MeetingTranscriptApp` executable/module/storage compatibility.

---

### Task 1: Release App and DMG Script

**Files:**
- Modify: `MeetingTranscriptApp/Resources/Info.plist`
- Modify: `scripts/build-macos-app.sh`
- Create: `scripts/build-release-dmg.sh`
- Modify: `Tests/MeetingTranscriptAppTests/BrandingTests.swift`

**Interfaces:**
- Produces: `BUILD_CONFIGURATION=release scripts/build-macos-app.sh` creating `.build/app/Meet Note.app`.
- Produces: `scripts/build-release-dmg.sh` creating `.build/dist/Meet Note.dmg`.

- [ ] **Step 1: Write failing packaging contract tests**

Extend `BrandingTests` to assert `CFBundleShortVersionString == "1.0.0"`, `CFBundleVersion == "1"`, the app script uses `${BUILD_CONFIGURATION:-debug}`, and the DMG script contains the required output path, Applications symlink, Release configuration, `codesign --verify`, and `hdiutil create`.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter BrandingTests`

Expected: FAIL because version keys and DMG script are absent.

- [ ] **Step 3: Implement minimal packaging changes**

Parameterize only the configuration and executable path in `build-macos-app.sh`. Add version keys to `Info.plist`. Build the Release app, stage it with a relative `Applications -> /Applications` symlink and `安裝說明.txt`, verify its ad-hoc signature, remove stale DMG output, and run compressed UDZO `hdiutil create`.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter BrandingTests`

Expected: PASS.

- [ ] **Step 5: Build and inspect the DMG**

Run: `scripts/build-release-dmg.sh`

Run: `hdiutil attach -nobrowse -readonly ".build/dist/Meet Note.dmg"`

Verify the mounted image contains `Meet Note.app`, `Applications`, and `安裝說明.txt`; run `plutil -p` on the mounted app's Info.plist, `file` on its executable, and `codesign --verify --deep --strict`. Detach the image.

- [ ] **Step 6: Run the complete test suite**

Run: `swift test`

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add MeetingTranscriptApp/Resources/Info.plist scripts Tests/MeetingTranscriptAppTests/BrandingTests.swift docs/superpowers
git commit -m "build: package Meet Note internal DMG"
```
