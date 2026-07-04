#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

swift build -c debug ${SWIFT_BUILD_FLAGS:-}

EXECUTABLE=".build/debug/MeetingTranscriptApp"
APP_DIR=".build/app/MeetingTranscriptApp.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="MeetingTranscriptApp/Resources"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Missing executable: $EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/MeetingTranscriptApp"
cp "$RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

xattr -cr "$APP_DIR"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
    if ! xattr -p com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1; then
        break
    fi
    sleep 0.3
done

codesign \
    --force \
    --sign - \
    --entitlements "$RESOURCES_DIR/MeetingTranscriptApp.entitlements" \
    "$APP_DIR"

for _ in 1 2 3 4 5 6 7 8 9 10; do
    xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
    if codesign --verify --deep --strict --verbose=4 "$APP_DIR"; then
        echo "Built app: $REPO_ROOT/$APP_DIR"
        echo "Open with: open $APP_DIR"
        exit 0
    fi
    sleep 0.3
done

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
