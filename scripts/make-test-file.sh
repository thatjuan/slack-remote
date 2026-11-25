#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf '%s\n' "Usage: $0 OUTPUT_PATH" >&2
    exit 2
fi

umask 077
set -C
printf '%s\n' 'Synthetic slack-remote upload fixture.' > "$1"
