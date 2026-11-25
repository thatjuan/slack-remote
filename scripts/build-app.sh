#!/bin/sh
set -eu

usage() {
    printf 'Usage: %s [--sign IDENTITY] [--output DIR]\n' "$0" >&2
    exit 2
}

identity=-
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
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
/usr/bin/swift build -c release --product slack-remote >&2
/usr/bin/swift build -c release --product SlackRemoteHelper >&2
build_dir=$(/usr/bin/swift build -c release --show-bin-path)
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

/usr/bin/codesign --force --options runtime --timestamp=none --sign "$identity" \
    --identifier slack-remote "$app/Contents/Helpers/slack-remote"
/usr/bin/codesign --force --options runtime --timestamp=none --sign "$identity" \
    --identifier com.thatjuan.slack-remote.helper "$app"
/usr/bin/codesign --verify --strict --deep "$app"

/bin/rm -rf "$output/SlackRemote.app"
/bin/mv "$app" "$output/SlackRemote.app"
if [ "$identity" = - ]; then
    printf 'Ad hoc signing: macOS will ask for Accessibility access again after every rebuild.\n' >&2
fi
printf '%s\n' "$output/SlackRemote.app"
