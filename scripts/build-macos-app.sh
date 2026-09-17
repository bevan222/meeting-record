#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"

swift build -c "$BUILD_CONFIGURATION" ${SWIFT_BUILD_FLAGS:-}

EXECUTABLE=".build/$BUILD_CONFIGURATION/MeetingTranscriptApp"
APP_DIR=".build/app/Meet Note.app"
LEGACY_APP_DIR=".build/app/MeetingTranscriptApp.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_RESOURCES_DIR="$CONTENTS_DIR/Resources"
RESOURCES_DIR="MeetingTranscriptApp/Resources"
ASSET_CATALOG="$RESOURCES_DIR/Assets.xcassets"
ASSET_INFO_PLIST=".build/app/assetcatalog-info.plist"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Missing executable: $EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_DIR" "$LEGACY_APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/MeetingTranscriptApp"
cp "$RESOURCES_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
rm -f "$ASSET_INFO_PLIST"
xcrun actool \
    --compile "$APP_RESOURCES_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_INFO_PLIST" \
    "$ASSET_CATALOG"

xattr -cr "$APP_DIR"
signed=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
    if codesign \
        --force \
        --sign - \
        --entitlements "$RESOURCES_DIR/MeetingTranscriptApp.entitlements" \
        "$APP_DIR"; then
        signed=true
        break
    fi
    sleep 0.3
done

if [[ "$signed" != true ]]; then
    echo "Could not sign app bundle: $APP_DIR" >&2
    exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
    xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
    if codesign --verify --deep --strict --verbose=4 "$APP_DIR"; then
        echo "Built app: $REPO_ROOT/$APP_DIR"
        echo "Open with: open \"$APP_DIR\""
        exit 0
    fi
    sleep 0.3
done

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
