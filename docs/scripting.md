# Scripting slack-remote

Check the exit status before parsing stdout. On success the CLI writes one JSON document to stdout. A command failure writes one JSON document to stderr. Keep the streams separate. `inspect` prints an Accessibility tree on success, and `--version` prints a version string. Help and argument errors are plain text. Omit `--debug` when parsing stderr because debug diagnostics add text.

```json
{
  "ok": true,
  "command": "dest list",
  "warnings": [],
  "result": { "destinations": {} }
}
```

```json
{
  "ok": false,
  "command": "read",
  "error": {
    "code": "ui_drift",
    "message": "Slack's Accessibility tree did not match the expected structure.",
    "details": { "locator": "primaryView", "found": 0 }
  }
}
```

`slackVersion` appears when the command knows the Slack version. On failure, `warnings`, `result` and `error.details` may be absent. For example, `doctor` can include its checks on failure, and a directory listing can include the items it collected before stopping. Branch on `error.code`. Use `message` and `details` for diagnostics.

For `accessibility_not_trusted`, `error.details` always includes `settingsUrl`. When the host app is detected, it also includes `hostApp` (name), `hostPath`, and `hostBundleId` when known. All four values are strings. `hostApp` is a best guess from the parent process chain; SSH and tmux sessions may have no detectable host app. Run `slack-remote doctor --grant` from the host app to request access and open Settings; ordinary commands fail without showing UI.

## Exit statuses

| Status | Error codes and conditions |
| --- | --- |
| 0 | Success, help or version |
| 1 | `internal`, `ax_failure`, `not_implemented` |
| 10 | `no_gui_session`, `screen_locked`, `accessibility_not_trusted` |
| 11 | `slack_not_running`, `ambiguous_slack`, `slack_window_unavailable`, `slack_not_ready`, `tree_unavailable` |
| 12 | `ui_drift`, `ambiguous_window`, `ui_blocked`, `overlay_left_open` |
| 13 | `destination_mismatch`, `destination_unreachable`, `message_not_rendered`, `unsupported_destination` |
| 14 | `slack_in_use`, `busy` |
| 15 | `unsafe_text`, `draft_conflict`, `write_not_allowed`, `file_rejected` |
| 16 | `write_failed`, `write_unverified` |
| 17 | `send_unconfirmed`, `reaction_unconfirmed`, `upload_unconfirmed` |
| 18 | `timeout` |
| 19 | `partial_result` |
| 20 | `account_mismatch`, `account_unverified`, `config_invalid` |
| 64 | Invalid syntax or option values, reported by Swift Argument Parser |
| 130 | `interrupted`. Search also uses status 130 if cancellation cleanup reports another error code. |

## List results

Message reads, directory lists and search return `complete`, `stopReason` and `pages`. `complete` is true at a verified `boundary` or `end_of_list`. `pages` counts Accessibility snapshots. An in-place rendered conversation read reports zero pages. Reaching a caller-supplied cap reports `limit` and exits 0. If paging stalls or reaches its deadline before satisfying the requested bounds, the command exits 19 unless you pass `--allow-partial`. With that flag, inspect `complete` and the `stalled` or `deadline` stop reason on stdout.

## Command effects

| Effect | Commands |
| --- | --- |
| No Slack content or lasting view change | `doctor`, `current`, `inspect`, `read` without a destination, `channels` from the sidebar, `dest list`, `dest add`, `whoami`, `whoami --save` and available `--dry-run` modes. `dest add` and `whoami --save` write local configuration. `whoami` can open and close an account lookup popup. |
| View only | `open`, `read` with a destination, history or thread, `members`, `people`, `channels --source browser`, and `search`. Lists and search attempt to restore the starting view when they switch views. Search can record recent queries. Search with `--open` leaves the verified result open. Opening a conversation or thread marks it viewed. |
| Slack content | `draft set`, `draft clear`, `send`, `reply`, `react` and `upload`. These also can change the view. |

Run one command at a time. Concurrent callers share a lock, and a caller that exhausts its timeout waiting for it receives `busy`. Stop on `ui_drift`, which can occur after a Slack update. On `send_unconfirmed`, `upload_unconfirmed` or `reaction_unconfirmed`, read the conversation or thread before deciding whether to retry. Slack may already have applied the change.

Set `SLACK_REMOTE_CONFIG` to use a private config file at a different path. The CLI requires the file to be owned by the current user and to exclude group and other permissions.

## Resolve a destination, read history and reply

Set `SINCE` to a Slack message timestamp earlier than the known parent message and `ROOT_TS` to that parent’s timestamp. The example uses the configured alias `notes`, checks that history contains the exact parent, and sends one threaded reply. It requires `jq` and a parent rendered when the reply opens.

```sh
#!/bin/sh
set -eu

: "${SINCE:?Set SINCE to a Slack timestamp earlier than the parent}"
: "${ROOT_TS:?Set ROOT_TS to the verified parent message timestamp}"
destination=notes

destinations=$(slack-remote dest list) || exit "$?"
target=$(printf '%s\n' "$destinations" |
    jq -ce --arg name "$destination" '.result.destinations[$name]') || exit "$?"
team=$(printf '%s\n' "$target" | jq -er '.team') || exit "$?"
channel=$(printf '%s\n' "$target" | jq -er '.conversation') || exit "$?"

history=$(slack-remote read --team "$team" --channel "$channel" \
    --history --since "$SINCE" --max-pages 1) || exit "$?"
parent=$(printf '%s\n' "$history" |
    jq -er --arg ts "$ROOT_TS" '.result.messages[] | select(.ts == $ts) | .ts') || exit "$?"

receipt=$(slack-remote reply --team "$team" --channel "$channel" \
    --thread "$parent" --text "slack-remote test scripting reply") || exit "$?"
printf '%s\n' "$receipt" | jq -e '.result | select(.sent == true)'
```

Run `scripts/check-json.sh notes` from a source checkout to check the JSON produced by commands that do not write Slack content. It takes a channel alias and an optional search query. Use `SLACK_REMOTE_BIN` to test a particular binary.
