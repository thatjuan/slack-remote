# slack-remote

`slack-remote` controls the stock Slack desktop client on macOS using Slack's documented deep links and macOS Accessibility.

Build with `swift build -c release`. Run `.build/release/slack-remote doctor` inside the logged-in user's macOS session with the screen unlocked and Slack running and visible. Grant the app that launches the CLI access in **System Settings › Privacy & Security › Accessibility**.

## Commands

| Command | Slack changes |
| --- | --- |
| [`doctor`](docs/commands/doctor.md), [`current`](docs/commands/current.md), [`inspect`](docs/commands/inspect.md), [`dest`](docs/commands/dest.md), `read` without a destination, any `--dry-run` | None. `dest add` edits the local config. |
| [`open`](docs/commands/open.md), [`read`](docs/commands/read.md) with a destination or `--history`, [`whoami`](docs/commands/whoami.md) | Conversation, scroll position, or a popup opened and closed. Slack marks a conversation as viewed when the tool opens it, which can clear unread markers. |
| [`draft`](docs/commands/draft.md), [`send`](docs/commands/send.md) | Composer or conversation content. |

Commands accept `--timeout <seconds>` (default 15) and `--debug` for aggregate diagnostics on stderr. Success is JSON on stdout. `inspect` prints plain text. Failures are JSON on stderr, and argument errors include usage. Other assistive tools that toggle Slack's Accessibility mode can interrupt a command with `tree_unavailable`. Rerun the command after the tree is available.

History has no verified conversation-start marker. It never reports `end_of_list`.

## Config and account checks

Use `whoami --save` to record the current workspace account in `~/.config/slack-remote/config.json`. The config uses mode `0600`. Set `SLACK_REMOTE_CONFIG` to use a separate private file. Use `dest add` to give a workspace and conversation pair a name, then address it with `--dest NAME`.

For commands that take a destination, a saved account is checked after navigation. With a config present, writes require a verified account in the target workspace. With no config, writes report `no_account_configured`. Set `restrictWritesToDestinations` to `true` in the config to limit writes to the exact pairs saved by `dest add`.

## Exit statuses

| Status | Codes |
| --- | --- |
| `0` | Success |
| `1` | `internal`, `ax_failure`, `not_implemented` |
| `10` | `no_gui_session`, `screen_locked`, `accessibility_not_trusted` |
| `11` | `slack_not_running`, `ambiguous_slack`, `slack_window_unavailable`, `slack_not_ready`, `tree_unavailable` |
| `12` | `ui_drift`, `ambiguous_window`, `ui_blocked`, `overlay_left_open` |
| `13` | `destination_mismatch`, `destination_unreachable`, `message_not_rendered`, `unsupported_destination` |
| `14` | `slack_in_use`, `busy` |
| `15` | `unsafe_text`, `draft_conflict`, `write_not_allowed`, `file_rejected` |
| `16` | `write_failed`, `write_unverified` |
| `17` | `send_unconfirmed`, `reaction_unconfirmed`, `upload_unconfirmed` |
| `18` | `timeout` |
| `19` | `partial_result` |
| `20` | `account_mismatch`, `account_unverified`, `config_invalid` |
| `64` | Argument error |
| `130` | Interrupted during an Accessibility tree session |
