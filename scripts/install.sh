#!/bin/sh
set -eu

prefix="$HOME/.local"
if [ "$#" -ne 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != "--prefix" ] || [ -z "$2" ]; then
        printf 'Usage: %s [--prefix DIR]\n' "$0" >&2
        exit 2
    fi
    prefix="$2"
fi
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
cd "$(dirname "$0")/.."
swift build -c release -Xlinker -adhoc_codesign
binary=.build/release/slack-remote
version=$("$binary" --version)
mkdir -p "$prefix/bin"
staged=$(mktemp -d "$prefix/bin/.slack-remote.XXXXXXXX")
trap 'rm -rf "$staged"' EXIT
trap 'exit 1' HUP INT TERM
install -m 755 "$binary" "$staged/slack-remote"
if [ -e "$target" ]; then
    check_target
    mv -fh "$staged/slack-remote" "$target"
else
    # Linking into an empty slot also catches a concurrent first install.
    ln -h "$staged/slack-remote" "$target"
fi
printf 'Installed %s (%s)\n' "$target" "$version"
