# slack-remote

`slack-remote` controls the stock Slack desktop client on macOS. It uses Slack's documented deep links and macOS Accessibility to inspect the current view and open a conversation. It verifies the workspace and conversation IDs before reporting that navigation succeeded.

Run it from inside the logged-in user's macOS session with the screen unlocked and Slack running and visible. Grant Accessibility permission to the app that launches the CLI in **System Settings › Privacy & Security › Accessibility**.

## Build

```sh
swift build -c release
```

## Commands

```sh
.build/release/slack-remote doctor
.build/release/slack-remote current
.build/release/slack-remote open --team T0AAAAAAA --channel C0BBBBBBB
```

- `doctor` reports the session, permission, Slack version, and Accessibility structure checks.
- `current` reports the conversation ID and workspace ID, or the path for another Slack view.
- `open` takes a channel, DM, or group conversation ID. For a DM, `--user <USER_ID>` selects the user deep link. Without it, Slack must have rendered the DM's sidebar row. Group conversations also use the sidebar. Pass `--interrupt` to allow navigation while Slack is in the foreground and has recent user input.

Each command accepts `--timeout <seconds>` (default `15`) and `--debug` for aggregate diagnostics on stderr. Commands write successful JSON to stdout and failure JSON to stderr. ArgumentParser reports usage errors separately.

## Exit statuses

| Status | Meaning |
| --- | --- |
| `0` | Success |
| `1` | `internal`, `ax_failure` |
| `10` | `no_gui_session`, `screen_locked`, `accessibility_not_trusted` |
| `11` | `slack_not_running`, `ambiguous_slack`, `slack_window_unavailable`, `slack_not_ready`, `tree_unavailable` |
| `12` | `ui_drift`, `ambiguous_window`, `ui_blocked` |
| `13` | `destination_mismatch`, `destination_unreachable` |
| `14` | `slack_in_use`, `busy` |
| `15` | `unsafe_text`, `draft_conflict` |
| `16` | `write_failed`, `write_unverified`, `send_not_performed` |
| `17` | `send_unconfirmed` |
| `18` | `timeout` |
| `64` | Argument error |
| `130` | Interrupted during an Accessibility tree session |
