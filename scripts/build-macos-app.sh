#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

swift build -c debug

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

codesign \
    --force \
    --sign - \
    --entitlements "$RESOURCES_DIR/MeetingTranscriptApp.entitlements" \
    "$APP_DIR"

echo "Built app: $REPO_ROOT/$APP_DIR"
echo "Open with: open $APP_DIR"
