#!/bin/sh
set -eu

usage() {
    printf 'Usage: %s [--prefix DIR] [--sign IDENTITY]\n' "$0" >&2
    exit 2
}

prefix="$HOME/.local"
identity=-
while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] && [ -n "$2" ] || usage
    case "$1" in
        --prefix) prefix=$2 ;;
        --sign) identity=$2 ;;
        *) usage ;;
    esac
    shift 2
done
case "$prefix" in
    /*) ;;
    *) prefix="$PWD/$prefix" ;;
esac

target="$prefix/bin/slack-remote"
check_target() {
    if [ -L "$target" ] || { [ -e "$target" ] && ! {
        [ -f "$target" ] && [ -x "$target" ] &&
            /usr/bin/codesign --verify --strict "$target" 2>/dev/null &&
            /usr/bin/codesign -dv "$target" 2>&1 | /usr/bin/grep -qx 'Identifier=slack-remote'
    }; }; then
        printf 'Refusing to overwrite %s\n' "$target" >&2
        exit 1
    fi
}

check_target
cd "$(/usr/bin/dirname "$0")/.."
. scripts/lib/app-install.sh
work=$(/usr/bin/mktemp -d)
staged=
trap '/bin/rm -rf "$work"; [ -z "$staged" ] || /bin/rm -rf "$staged"' EXIT
trap 'exit 1' HUP INT TERM
app=$(scripts/build-app.sh --sign "$identity" --output "$work")
binary="$app/Contents/Helpers/slack-remote"
version=$("$binary" --version)
/bin/mkdir -p "$prefix/bin"
staged=$(/usr/bin/mktemp -d "$prefix/bin/.slack-remote.XXXXXXXX")
/usr/bin/install -m 755 "$binary" "$staged/slack-remote"
if [ -e "$target" ]; then
    check_target
    /bin/mv -fh "$staged/slack-remote" "$target"
else
    # Linking into an empty slot also catches a concurrent first install.
    /bin/ln -h "$staged/slack-remote" "$target"
fi
printf 'Installed %s (%s)\n' "$target" "$version"
install_app "$app"
