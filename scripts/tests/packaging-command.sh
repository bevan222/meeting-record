#!/bin/bash
set -euo pipefail

# External tools are replaced only inside the self-test's disposable repository.
case "$(basename "$0")" in
    swift)
        configuration=debug
        backend=native
        while (( $# )); do
            case "$1" in
                -c) configuration="$2"; shift ;;
                --build-system) backend="$2"; shift ;;
                --show-bin-path) show_path=true ;;
            esac
            shift
        done
        if [[ "${show_path:-false}" == true ]]; then
            if [[ "$backend" == xcode ]]; then
                case "$configuration" in
                    release) output=Release ;;
                    debug) output=Debug ;;
                    *) exit 47 ;;
                esac
                printf '%s/.build/apple/Products/%s\n' "$PWD" "$output"
            else
                printf '%s/.build/arm64-apple-macosx/%s\n' "$PWD" "$configuration"
            fi
        fi
        ;;
    lipo) echo arm64 ;;
    vtool)
        [[ "${FAIL_AT:-}" != verifier ]] || exit 42
        echo '    minos 14.0'
        ;;
    xcrun|xattr|codesign|sleep) ;;
    mv)
        [[ "${FAIL_AT:-}" != publication ]] || exit 46
        exec /bin/mv "$@"
        ;;
    hdiutil)
        action="$1"
        shift
        case "$action" in
            create)
                while (( $# )); do
                    case "$1" in
                        -srcfolder) source="$2"; shift ;;
                    esac
                    image="$1"
                    shift
                done
                printf '%s\n' "$image" > "$TEST_ROOT/created-path"
                cp '.build/dist/Meet Note.dmg' "$TEST_ROOT/final-at-create" 2>/dev/null || true
                printf 'candidate image\n' > "$image"
                [[ "${FAIL_AT:-}" != creator ]] || exit 41
                ditto "$source" "$TEST_ROOT/image-contents"
                ;;
            attach)
                while (( $# )); do
                    case "$1" in
                        -mountpoint) mount_point="$2"; shift ;;
                    esac
                    image="$1"
                    shift
                done
                printf '%s\n' "$image" > "$TEST_ROOT/verified-path"
                ditto "$TEST_ROOT/image-contents" "$mount_point"
                ;;
            detach)
                cp '.build/dist/Meet Note.dmg' "$TEST_ROOT/final-at-detach" 2>/dev/null || true
                [[ "${FAIL_AT:-}" != detach ]] || exit 43
                # Real detach exposes the empty underlying mount directory.
                find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                ;;
            *) exit 44 ;;
        esac
        ;;
    *) exit 45 ;;
esac
