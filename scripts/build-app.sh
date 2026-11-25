#!/bin/sh
set -eu

usage() {
    printf 'Usage: %s [--universal] [--sign IDENTITY] [--output DIR]\n' "$0" >&2
    exit 2
}

identity=-
output=
universal=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --universal)
            universal=true
            shift
            ;;
        --sign)
            [ "$#" -ge 2 ] && [ -n "$2" ] || usage
            identity=$2
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] && [ -n "$2" ] || usage
            output=$2
            shift 2
            ;;
        *) usage ;;
    esac
done
case "$output" in
    ''|/*) ;;
    *) output="$PWD/$output" ;;
esac

cd "$(/usr/bin/dirname "$0")/.."
output=${output:-"$PWD/dist"}
if "$universal"; then
    set -- --arch arm64 --arch x86_64 -Xlinker -adhoc_codesign
fi
/usr/bin/swift build -c release "$@" >&2
build_dir=$(/usr/bin/swift build -c release "$@" --show-bin-path)
if "$universal"; then
    for binary in "$build_dir/slack-remote" "$build_dir/SlackRemoteHelper"; do
        case "$(/usr/bin/lipo -archs "$binary")" in
            'arm64 x86_64'|'x86_64 arm64') ;;
            *) printf 'Expected arm64 and x86_64 slices in %s\n' "$binary" >&2; exit 1 ;;
        esac
    done
fi
version=$("$build_dir/slack-remote" --version)

/bin/mkdir -p "$output"
staging=$(/usr/bin/mktemp -d "$output/.build-app.XXXXXXXX")
trap '/bin/rm -rf "$staging"' EXIT
trap 'exit 1' HUP INT TERM
app="$staging/SlackRemote.app"
/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
/bin/cp scripts/app/Info.plist "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
/usr/bin/install -m 755 "$build_dir/SlackRemoteHelper" "$app/Contents/MacOS/SlackRemote"
/usr/bin/install -m 755 "$build_dir/slack-remote" "$app/Contents/Helpers/slack-remote"

timestamp=--timestamp
if [ "$identity" = - ]; then
    timestamp=--timestamp=none
fi
/usr/bin/codesign --force --options runtime "$timestamp" --sign "$identity" \
    --identifier slack-remote "$app/Contents/Helpers/slack-remote"
/usr/bin/codesign --force --options runtime "$timestamp" --sign "$identity" \
    --identifier com.thatjuan.slack-remote.helper "$app"
/usr/bin/codesign --verify --strict --deep "$app"

/bin/rm -rf "$output/SlackRemote.app"
/bin/mv "$app" "$output/SlackRemote.app"
if [ "$identity" = - ]; then
    printf '%s\n' 'SlackRemote.app is signed ad hoc. macOS will ask for Accessibility again after every rebuild. Pass --sign "<certificate name>" to keep the grant; see README "Build from source".' >&2
fi
printf '%s\n' "$output/SlackRemote.app"
