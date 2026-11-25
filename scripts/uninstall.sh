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
if [ -L "$target" ] || { [ -e "$target" ] && ! {
    [ -f "$target" ] && [ -x "$target" ] &&
        /usr/bin/codesign --verify --strict "$target" 2>/dev/null &&
        /usr/bin/codesign -dv "$target" 2>&1 | /usr/bin/grep -qx 'Identifier=slack-remote'
}; }; then
    printf 'Refusing to remove %s\n' "$target" >&2
    exit 1
fi
if [ -f "$target" ]; then
    rm "$target"
    printf 'Removed %s\n' "$target"
else
    printf 'Already absent %s\n' "$target"
fi
printf 'Kept %s\n' "$HOME/.config/slack-remote" "$HOME/Library/Application Support/slack-remote"
