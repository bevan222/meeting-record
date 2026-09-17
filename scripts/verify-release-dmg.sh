#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_PATH="${1:-$REPO_ROOT/.build/dist/Meet Note.dmg}"
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/meet-note-dmg-mount.XXXXXX")"
MOUNTED=false

fail() {
    echo "DMG verification failed: $1" >&2
    exit 1
}

cleanup() {
    if [[ "$MOUNTED" == true ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}

trap cleanup EXIT

[[ -f "$DMG_PATH" ]] || fail "missing DMG: $DMG_PATH"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
MOUNTED=true

expected_entries=$'Applications\nMeet Note.app\n安裝說明.txt'
actual_entries="$(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
[[ "$actual_entries" == "$expected_entries" ]] || fail "unexpected root entries"
[[ -L "$MOUNT_POINT/Applications" ]] || fail "Applications is not a symlink"
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || fail "Applications symlink target is incorrect"

expected_note=$'將 Meet Note.app 拖曳至 Applications 資料夾。\n首次開啟請以滑鼠右鍵點選 Meet Note，選擇「打開」。'
[[ "$(cat "$MOUNT_POINT/安裝說明.txt")" == "$expected_note" ]] || fail "installation note is incorrect"

APP_PATH="$MOUNT_POINT/Meet Note.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/MeetingTranscriptApp"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO_PLIST")" == "Meet Note" ]] || fail "display name is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")" == "Meet Note" ]] || fail "bundle name is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")" == "MeetingTranscriptApp" ]] || fail "bundle executable is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" == "1.0.0" ]] || fail "bundle version is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")" == "1" ]] || fail "bundle build is incorrect"

lipo -archs "$EXECUTABLE" | tr ' ' '\n' | grep -qx arm64 || fail "packaged executable is not arm64"

if command -v vtool >/dev/null; then
    minimum_macos="$(vtool -show-build "$EXECUTABLE" | awk '$1 == "minos" { print $2; exit }')"
    if [[ -n "$minimum_macos" ]]; then
        [[ "$minimum_macos" == "14.0" ]] || fail "minimum macOS version is $minimum_macos"
    else
        echo "DMG verification: unable to parse minimum macOS version" >&2
    fi
fi

codesign --verify --deep --strict --verbose=4 "$APP_PATH"
echo "Verified DMG: $DMG_PATH"
