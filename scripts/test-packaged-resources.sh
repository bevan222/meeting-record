#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$REPO_ROOT/.build/app/Meet Note.app}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
case "$BUILD_CONFIGURATION" in
    release) CONFIGURATION_DIR=Release ;;
    debug) CONFIGURATION_DIR=Debug ;;
    *) echo "Unsupported configuration: $BUILD_CONFIGURATION" >&2; exit 1 ;;
esac
ACCESSOR="$REPO_ROOT/.build/apple/Intermediates.noindex/swift-transformers.build/$CONFIGURATION_DIR/Hub_Module.build/DerivedSources/resource_bundle_accessor.swift"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meet-note-resource-probe.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Exercise the real generated accessor in a relocated app without modifying the release.
ditto "$APP_PATH" "$TEMP_DIR/Meet Note.app"
PROBE="$TEMP_DIR/Meet Note.app/Contents/MacOS/MeetingTranscriptApp"
rm -f "$PROBE"
swiftc -target arm64-apple-macosx14.0 "$ACCESSOR" "$SCRIPT_DIR/tests/resource-bundle-probe.swift" -o "$PROBE"
"$PROBE"
