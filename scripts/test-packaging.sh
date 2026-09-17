#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/meet-note-packaging-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
failures=0

check() {
    if ! "$@"; then
        echo "FAIL [$test_case]: $*" >&2
        failures=$((failures + 1))
    fi
}

for test_case in creator verifier detach publication creator-empty verifier-empty detach-empty publication-empty final-directory success resources missing-resource verifier-missing-resource verifier-unsealed-root; do
    TEST_ROOT="$ROOT/$test_case"
    export TEST_ROOT
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/bin" "$TEST_ROOT/tmp" "$TEST_ROOT/.build/dist"
    cp "$SCRIPT_DIR/"{build-macos-app,build-release-dmg,verify-release-dmg}.sh "$TEST_ROOT/scripts/"
    for command in swift lipo vtool xcrun xattr codesign sleep hdiutil mv; do
        cp "$SCRIPT_DIR/tests/packaging-command.sh" "$TEST_ROOT/bin/$command"
        chmod +x "$TEST_ROOT/bin/$command"
    done
    mkdir -p "$TEST_ROOT/MeetingTranscriptApp"
    cp -R "$SCRIPT_DIR/../MeetingTranscriptApp/Resources" "$TEST_ROOT/MeetingTranscriptApp/"
    build_dir="$TEST_ROOT/.build/apple/Products/Release"
    mkdir -p "$build_dir" "$TEST_ROOT/.build/release"
    cp /usr/bin/true "$build_dir/MeetingTranscriptApp"
    cp /usr/bin/true "$TEST_ROOT/.build/release/MeetingTranscriptApp"
    for bundle in swift-transformers_Hub.bundle 'Another Resource.bundle'; do
        mkdir -p "$build_dir/$bundle/Contents/Resources"
        printf 'release resource\n' > "$build_dir/$bundle/Contents/Resources/payload.txt"
        if [[ "$test_case" == resources ]]; then
            chmod a-w "$build_dir/$bundle/Contents/Resources/payload.txt"
        fi
    done
    printf 'previous verified DMG\n' > "$TEST_ROOT/sentinel"
    cp "$TEST_ROOT/sentinel" "$TEST_ROOT/.build/dist/Meet Note.dmg"
    case "$test_case" in
        *-empty) rm "$TEST_ROOT/.build/dist/Meet Note.dmg" ;;
        final-directory)
            rm "$TEST_ROOT/.build/dist/Meet Note.dmg"
            mkdir "$TEST_ROOT/.build/dist/Meet Note.dmg"
            ;;
    esac

    if [[ "$test_case" == missing-resource ]]; then
        rm -rf "$build_dir/swift-transformers_Hub.bundle"
    fi

    status=0
    (
        cd "$TEST_ROOT"
        export PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/tmp"
        export FAIL_AT="${test_case%-empty}"
        case "$test_case" in
            resources|missing-resource)
                BUILD_CONFIGURATION=release bash scripts/build-macos-app.sh
                ;;
            verifier-missing-resource|verifier-unsealed-root)
                BUILD_CONFIGURATION=release bash scripts/build-macos-app.sh
                mkdir -p "$TEST_ROOT/image-contents"
                ditto '.build/app/Meet Note.app' "$TEST_ROOT/image-contents/Meet Note.app"
                ln -s /Applications "$TEST_ROOT/image-contents/Applications"
                printf '將 Meet Note.app 拖曳至 Applications 資料夾。\n首次開啟請以滑鼠右鍵點選 Meet Note，選擇「打開」。\n' > "$TEST_ROOT/image-contents/安裝說明.txt"
                if [[ "$test_case" == verifier-missing-resource ]]; then
                    rm -rf "$TEST_ROOT/image-contents/Meet Note.app/Contents/Resources/swift-transformers_Hub.bundle"
                else
                    ln -sf Contents/Resources/swift-transformers_Hub.bundle "$TEST_ROOT/image-contents/Meet Note.app/unsealed-resource"
                fi
                bash scripts/verify-release-dmg.sh '.build/dist/Meet Note.dmg'
                ;;
            *) bash scripts/build-release-dmg.sh ;;
        esac
    ) > "$TEST_ROOT/output" 2>&1 || status=$?

    case "$test_case" in
        creator|verifier|detach|publication)
            check test "$status" -ne 0
            check cmp "$TEST_ROOT/sentinel" "$TEST_ROOT/.build/dist/Meet Note.dmg"
            check test "$(find "$TEST_ROOT/.build/dist" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1
            check test "$(find "$TEST_ROOT/tmp" -maxdepth 1 -name 'meet-note-dmg.*' | wc -l | tr -d ' ')" = 0
            ;;
        *-empty)
            check test "$status" -ne 0
            check test "$(find "$TEST_ROOT/.build/dist" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 0
            ;;
        final-directory)
            check test "$status" -ne 0
            check test -d "$TEST_ROOT/.build/dist/Meet Note.dmg"
            check test "$(find "$TEST_ROOT/.build/dist/Meet Note.dmg" -mindepth 1 | wc -l | tr -d ' ')" = 0
            check test "$(find "$TEST_ROOT/.build/dist" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1
            ;;
        success)
            check test "$status" -eq 0
            check test "$(cat "$TEST_ROOT/.build/dist/Meet Note.dmg")" = 'candidate image'
            check cmp "$TEST_ROOT/sentinel" "$TEST_ROOT/final-at-create"
            check cmp "$TEST_ROOT/sentinel" "$TEST_ROOT/final-at-detach"
            check cmp "$TEST_ROOT/created-path" "$TEST_ROOT/verified-path"
            candidate="$(cat "$TEST_ROOT/created-path")"
            check test "$candidate" != '.build/dist/Meet Note.dmg'
            check test "${candidate#.build/dist/}" != "$candidate"
            check test "$(find "$TEST_ROOT/.build/dist" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1
            ;;
        resources)
            check test "$status" -eq 0
            for bundle in swift-transformers_Hub.bundle 'Another Resource.bundle'; do
                app="$TEST_ROOT/.build/app/Meet Note.app"
                check cmp "$build_dir/$bundle/Contents/Resources/payload.txt" "$app/Contents/Resources/$bundle/Contents/Resources/payload.txt"
                check test -w "$app/Contents/Resources/$bundle/Contents/Resources/payload.txt"
                check test ! -w "$build_dir/$bundle/Contents/Resources/payload.txt"
            done
            check test "$(find "$app" -mindepth 1 -maxdepth 1 -exec basename {} \;)" = Contents
            ;;
        missing-resource|verifier-missing-resource)
            check test "$status" -ne 0
            check grep -q 'swift-transformers_Hub.bundle' "$TEST_ROOT/output"
            ;;
        verifier-unsealed-root)
            check test "$status" -ne 0
            check grep -q 'unsealed' "$TEST_ROOT/output"
            ;;
    esac
done

[[ "$failures" == 0 ]] || { echo "$failures packaging assertions failed" >&2; exit 1; }
echo 'Packaging self-tests passed (14 scenarios)'
