#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

APP_DIR=".build/app/Meet Note.app"
DMG_PATH=".build/dist/Meet Note.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meet-note-dmg.XXXXXX")"

trap 'rm -rf "$STAGING_DIR"' EXIT

verify_app_signature() {
    local app_path="$1"

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        xattr -cr "$app_path"
        if codesign --verify --deep --strict --verbose=4 "$app_path"; then
            return 0
        fi
        sleep 0.3
    done

    echo "Could not verify app signature: $app_path" >&2
    return 1
}

BUILD_CONFIGURATION=release "$SCRIPT_DIR/build-macos-app.sh"

mkdir -p "$(dirname "$DMG_PATH")"
ditto "$APP_DIR" "$STAGING_DIR/Meet Note.app"
verify_app_signature "$STAGING_DIR/Meet Note.app"
ln -s /Applications "$STAGING_DIR/Applications"
printf '將 Meet Note.app 拖曳至 Applications 資料夾。\n首次開啟請以滑鼠右鍵點選 Meet Note，選擇「打開」。\n' > "$STAGING_DIR/安裝說明.txt"

rm -f "$DMG_PATH"
hdiutil create -volname "Meet Note" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
"$SCRIPT_DIR/verify-release-dmg.sh" "$DMG_PATH"

echo "Built DMG: $REPO_ROOT/$DMG_PATH"
