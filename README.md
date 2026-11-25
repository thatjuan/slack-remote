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

### `read`

`read` returns the current conversation's rendered messages in order from oldest to newest. Supply both `--team` and `--channel` to open and verify a conversation before reading it. The `--user` and `--interrupt` flags work as they do with `open`.

The result's `scope: "rendered"` means Slack's message list supplies only what it has drawn, usually the messages on screen and a small buffer. Reading the current conversation leaves it on screen at the same scroll position. By default `read` returns the full rendered list. Use `--limit N` to keep the newest N entries, or `--limit 0` to return an empty message array.

```sh
.build/release/slack-remote read --limit 5
```

### `draft`

`draft set` puts text in an empty composer and stops there. If the composer already holds the same text, the command succeeds with `method: "existing"`. A different draft or a pending attachment returns `draft_conflict`.

`draft clear` removes a draft that matches `--expect-text`. An empty composer succeeds with `cleared: false`. Draft comparisons use Unicode NFC, convert CRLF to LF, and ignore one trailing newline.

```sh
.build/release/slack-remote draft set --team T0AAAAAAA --channel C0BBBBBBB --text 'Ready for review'
.build/release/slack-remote draft clear --team T0AAAAAAA --channel C0BBBBBBB --expect-text 'Ready for review'
```

### `send`

`send` writes the message or reuses an identical draft. It rechecks the destination, composer, and send button before pressing once. A successful result includes the timestamp of the newer matching message that Slack rendered.

```sh
.build/release/slack-remote send --team T0AAAAAAA --channel C0BBBBBBB --text 'Ready for review'
```

All three commands require `--team` and `--channel` and accept `--user` for DM navigation. They refuse to proceed while Slack is frontmost and has received input within the last 30 seconds unless you pass `--interrupt`.

The CLI checks text before opening a Slack session. It refuses blank text, text over 4,000 characters, control characters other than newline and tab, a leading `/` after whitespace, and standalone reaction shortcuts such as `+:tada:`. It also refuses `@channel`, `@here`, and `@everyone` in any case. `send --allow-broadcast` permits those mentions.

If a failure reports `draftLeft: true` before the press, rerun `send` with the same text to resume an identical draft, or clear it with `draft clear --expect-text`. If Slack changed the text or the draft contains a broadcast mention, inspect and clear it in Slack. An error without `draftLeft` may mean the CLI could no longer verify the conversation.

`send_unconfirmed` means Slack may have sent the message. Use `read` or check the conversation in Slack before retrying. Each invocation makes at most one press.

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
