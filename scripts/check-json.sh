#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf 'Usage: %s DEST [QUERY]\n' "$0" >&2
    exit 2
fi

binary=${SLACK_REMOTE_BIN:-slack-remote}
destination=$1
query=${2:-slack-remote test}

check() {
    # Capture the command status separately so a parser cannot mask it.
    output=$("$binary" "$@") || return "$?"
    if ! printf '%s\n' "$output" | jq -e . >/dev/null ||
        ! printf '%s\n' "$output" | jq -es 'length == 1 and .[0].ok == true' >/dev/null; then
        printf 'Invalid success response from %s\n' "$*" >&2
        return 1
    fi
}

check doctor
check current
check whoami
check dest list
check open --dest "$destination"
check read
check read --dest "$destination" --history --max-pages 1
check channels --allow-partial
check members --dest "$destination" --allow-partial
check channels --source browser --allow-partial
check people --allow-partial
check search --query "$query" --in "$destination" --allow-partial
