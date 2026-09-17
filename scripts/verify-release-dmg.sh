#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HDIUTIL_COMMAND="${HDIUTIL_COMMAND:-hdiutil}"
VTOOL_COMMAND="${VTOOL_COMMAND:-vtool}"
SLEEP_COMMAND="${SLEEP_COMMAND:-sleep}"
DETACH_RETRIES="${DETACH_RETRIES:-3}"
MOUNT_POINT=""
MOUNTED=false

fail() {
    echo "DMG verification failed: $1" >&2
    exit 1
}

read_macos_deployment_target() {
    local vtool_output
    local deployment_target

    command -v "$VTOOL_COMMAND" >/dev/null 2>&1 || return 1
    vtool_output="$("$VTOOL_COMMAND" -show-build "$1")" || return 1
    deployment_target="$(printf '%s\n' "$vtool_output" | awk '$1 == "minos" { print $2; exit }')"
    [[ -n "$deployment_target" ]] || return 1
    printf '%s\n' "$deployment_target"
}

detach_mounted_image() {
    local attempt

    for ((attempt = 1; attempt <= DETACH_RETRIES; attempt++)); do
        if "$HDIUTIL_COMMAND" detach "$MOUNT_POINT" >/dev/null 2>&1; then
            MOUNTED=false
            return 0
        fi
        if (( attempt < DETACH_RETRIES )); then
            "$SLEEP_COMMAND" 0.2
        fi
    done

    return 1
}

cleanup_mount_point() {
    if [[ "$MOUNTED" == true ]] && ! detach_mounted_image; then
        return 1
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}

cleanup() {
    local status=$?

    trap - EXIT
    if ! cleanup_mount_point; then
        echo "DMG verification failed: could not detach $MOUNT_POINT" >&2
        exit 1
    fi
    exit "$status"
}

finish_success() {
    if ! cleanup_mount_point; then
        trap - EXIT
        fail "could not detach $MOUNT_POINT"
    fi
    trap - EXIT
    echo "Verified DMG: $1"
}

run_self_test() {
    local cleanup_output
    local cleanup_status
    local self_test_mount
    local failures=0

    self_test_mount="$(mktemp -d "${TMPDIR:-/tmp}/meet-note-dmg-self-test.XXXXXX")"

    VTOOL_COMMAND="meet-note-missing-vtool"
    if read_macos_deployment_target "$self_test_mount" >/dev/null; then
        echo "Self-test failed: missing vtool was accepted" >&2
        failures=1
    fi

    VTOOL_COMMAND=false
    if read_macos_deployment_target "$self_test_mount" >/dev/null; then
        echo "Self-test failed: failing vtool was accepted" >&2
        failures=1
    fi

    VTOOL_COMMAND=true
    if read_macos_deployment_target "$self_test_mount" >/dev/null; then
        echo "Self-test failed: unparsable vtool output was accepted" >&2
        failures=1
    fi

    MOUNT_POINT="$self_test_mount"
    MOUNTED=true
    HDIUTIL_COMMAND=false
    SLEEP_COMMAND=true
    DETACH_RETRIES=2
    if detach_mounted_image; then
        echo "Self-test failed: failing detach was accepted" >&2
        failures=1
    fi
    if [[ "$MOUNTED" != true ]]; then
        echo "Self-test failed: failed detach cleared mount state" >&2
        failures=1
    fi

    HDIUTIL_COMMAND=true
    if ! detach_mounted_image || [[ "$MOUNTED" != false ]]; then
        echo "Self-test failed: successful detach was not recorded" >&2
        failures=1
    fi

    if cleanup_output="$(
        (
            MOUNT_POINT="$self_test_mount"
            MOUNTED=true
            HDIUTIL_COMMAND=false
            SLEEP_COMMAND=true
            DETACH_RETRIES=2
            trap cleanup EXIT
            finish_success "self-test"
        ) 2>&1
    )"; then
        cleanup_status=0
    else
        cleanup_status=$?
    fi
    if [[ "$cleanup_status" == 0 ]]; then
        echo "Self-test failed: cleanup failure returned success" >&2
        failures=1
    fi
    if [[ "$cleanup_output" == *"Verified DMG:"* ]]; then
        echo "Self-test failed: cleanup failure reported verification success" >&2
        failures=1
    fi

    rmdir "$self_test_mount"
    [[ "$failures" == 0 ]] || return 1
    echo "Verifier self-test passed"
}

if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit
fi

[[ "$DETACH_RETRIES" =~ ^[1-9][0-9]*$ ]] || fail "invalid detach retry count: $DETACH_RETRIES"

DMG_PATH="${1:-$REPO_ROOT/.build/dist/Meet Note.dmg}"
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/meet-note-dmg-mount.XXXXXX")"
trap cleanup EXIT

[[ -f "$DMG_PATH" ]] || fail "missing DMG: $DMG_PATH"
"$HDIUTIL_COMMAND" attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
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
HUB_BUNDLE="swift-transformers_Hub.bundle"

[[ -d "$APP_PATH/Contents/Resources/$HUB_BUNDLE" ]] || fail "missing resource bundle: $HUB_BUNDLE"
[[ "$(find "$APP_PATH" -mindepth 1 -maxdepth 1 -exec basename {} \;)" == Contents ]] || fail "unsealed app-root contents"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO_PLIST")" == "Meet Note" ]] || fail "display name is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")" == "Meet Note" ]] || fail "bundle name is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")" == "MeetingTranscriptApp" ]] || fail "bundle executable is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" == "1.0.0" ]] || fail "bundle version is incorrect"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")" == "1" ]] || fail "bundle build is incorrect"

lipo -archs "$EXECUTABLE" | tr ' ' '\n' | grep -qx arm64 || fail "packaged executable is not arm64"
minimum_macos="$(read_macos_deployment_target "$EXECUTABLE")" || fail "could not read minimum macOS version"
case "$minimum_macos" in
    14.0|14.0.0) ;;
    *) fail "minimum macOS version is $minimum_macos" ;;
esac

codesign --verify --deep --strict --verbose=4 "$APP_PATH"
finish_success "$DMG_PATH"
