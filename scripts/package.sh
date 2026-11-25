#!/bin/sh
# Install the Developer ID Application certificate in the packaging Mac's login keychain.
# Set up notarization once with:
#   xcrun notarytool store-credentials <PROFILE> --apple-id … --team-id …
set -eu

usage() {
    printf 'Usage: %s [--sign IDENTITY] [--notarize PROFILE]\n' "$0" >&2
    exit 2
}

identity=-
profile=
while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] && [ -n "$2" ] || usage
    case "$1" in
        --sign) identity=$2 ;;
        --notarize) profile=$2 ;;
        *) usage ;;
    esac
    shift 2
done
if [ -n "$profile" ] && [ "$identity" = - ]; then
    printf 'Notarization requires --sign with a Developer ID Application identity.\n' >&2
    exit 2
fi

cd "$(/usr/bin/dirname "$0")/.."
/bin/mkdir -p dist
staged=$(/usr/bin/mktemp -d "$PWD/dist/.package.XXXXXXXX")
trap '/bin/rm -rf "$staged"' EXIT
trap 'exit 1' HUP INT TERM
app=$(scripts/build-app.sh --universal --sign "$identity" --output "$staged")
binary="$app/Contents/Helpers/slack-remote"
version=$("$binary" --version)
archive="slack-remote-$version-macos.zip"

/bin/mkdir "$staged/payload"
/usr/bin/ditto "$binary" "$staged/payload/slack-remote"
/bin/mv "$app" "$staged/payload/"
app="$staged/payload/SlackRemote.app"
/bin/cp README.md "$staged/payload/"
/bin/cp -R docs "$staged/payload/"

zip_payload() {
    /usr/bin/ditto -c -k --rsrc --sequesterRsrc "$staged/payload" "$staged/$archive"
}

zip_payload
if [ -n "$profile" ]; then
    /usr/bin/xcrun notarytool submit "$staged/$archive" --keychain-profile "$profile" \
        --wait --output-format json > "$staged/notary.json"
    /bin/cat "$staged/notary.json" >&2
    if [ "$(/usr/bin/plutil -extract status raw "$staged/notary.json")" != Accepted ]; then
        printf 'Notarization did not return Accepted.\n' >&2
        exit 1
    fi
    /usr/bin/xcrun stapler staple "$app" >&2
    zip_payload
fi

/usr/bin/ditto -x -k --rsrc "$staged/$archive" "$staged/verified"
/usr/bin/codesign --verify --strict --deep "$staged/verified/SlackRemote.app"
/usr/bin/codesign --verify --strict --all-architectures "$staged/verified/slack-remote"
(
    cd "$staged"
    /usr/bin/shasum -a 256 "$archive" > "$archive.sha256"
)
/bin/mv -f "$staged/$archive" "$staged/$archive.sha256" dist/
printf '%s\n' "$PWD/dist/$archive" "$PWD/dist/$archive.sha256"
