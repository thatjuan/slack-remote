# Validating the delivered CLI

How to check `slack-remote` once the milestone issues are implemented, and what evidence each pull request should carry. `evidence.md` lists what the planning probes observed; this file covers what remains to be shown.

## Inputs the coordinator supplies

Implementers never choose a Slack destination. Before live validation, set these in the environment of the session that runs it:

| Variable | Meaning | Needed for |
|---|---|---|
| `SLACK_REMOTE_TEST_TEAM` | Team id of the disposable destination | any step that navigates or writes |
| `SLACK_REMOTE_TEST_CHANNEL` | Conversation id of a disposable conversation | same |
| `SLACK_REMOTE_TEST_CHANNEL_2` | A second disposable conversation | draft persistence |
| `SLACK_REMOTE_TEST_DM`, `SLACK_REMOTE_TEST_USER` | A disposable DM and its user id | the `slack://user` route |
| `SLACK_REMOTE_TEST_ALLOW_SEND` | Set to `1` to permit live sends | live `send`, `reply`, `react` |

A disposable destination is a conversation Juan designates for testing, ideally in a throwaway workspace the Slack client is signed in to. Live sends are never run in a real workspace conversation. When the variables are absent, the steps that need them are skipped and the pull request says which.

## Three levels of validation

### 1. Unit tests, no Slack involved

```
swift build -c release
swift test
```

The tests run against fake trees built by `SlackFixture`. They cover URL parsing, destination verification, route selection, tree-mode ownership and restore, message extraction, the text rules, the composer state machine and the send state machine, including every case where send must not be pressed. They never reach the real client.

### 2. Read-only checks, allowed on any workspace

These commands only read. They do not navigate, focus, type or press.

1. `slack-remote doctor`: every check passes; note the settle time and node count.
2. `slack-remote current`: matches the conversation on screen.
3. `slack-remote read`: the newest message and the sender attribution match the screen.
4. After each command the conversation, scroll position and frontmost application are unchanged, and a second `doctor` reports that it had to enable the tree itself. That shows the previous command restored `AXManualAccessibility`.
5. Interrupt a command with Ctrl-C during the settle wait, then run `doctor`: the tree was off again and no `ax-enabled-*` marker remains in `~/Library/Application Support/slack-remote/`.
6. Run `doctor` from an ssh shell: it fails with `no_gui_session` or `accessibility_not_trusted`, exit status 10.
7. Run two commands at once: both complete in turn. Run one with a short `--timeout` while another holds the lock: `busy`, exit status 14.
8. Lock the screen and run `current` from a delayed shell command: `screen_locked`, exit status 10.

### 3. Checks against the disposable destination

Navigation: `open` reaches the test channel and reports the route; `open` with an id that does not exist fails with `destination_mismatch`; the DM routes with and without `--user`; whether Slack takes focus and whether focus is restored.

Draft: `draft set` puts the text in the composer and sends nothing; the draft survives navigating away and back; a second `draft set` with different text fails with `draft_conflict`; `draft clear` removes only the exact text; refused text never reaches Slack.

Send, only with `SLACK_REMOTE_TEST_ALLOW_SEND=1`: one `send` produces exactly one message in the test conversation with the returned timestamp; a retry over an identical draft resumes; a competing invocation waits on the lock.

The step-by-step lists are in each issue under "Live validation".

## Evidence expected in each pull request

- The `swift test` summary line.
- The `docs/validation/*.md` file for that issue, listing each live step as run or skipped, with outcomes.
- For skipped steps, the reason, which is usually that the disposable destination or send permission was not supplied.
- No message text, names, workspace names or URLs from a real workspace anywhere in the pull request.

## What the planning probes already showed

Observed directly on Slack 4.53.292 (see `evidence.md` for detail):

- The Accessibility permission state can be read without prompting.
- The session state (console, login done, lock key) can be read.
- `AXManualAccessibility` can be set and restored, the tree appears in about 2 s, and it is gone after restore.
- The web area URL carries the team and conversation ids.
- Sidebar rows, message items, the composer editor and the send button can all be located by role, class and id.
- A full tree walk takes under 0.1 s.
- The probe changed neither focus nor the conversation.

Not exercised by planning, by instruction: opening a link, pressing anything, typing anything, sending anything. Those are first exercised by the implementing issues under the rules above.

## Limits to state in the README

- The tool reads what Slack has rendered. It does not scroll or load history.
- It needs a process inside the logged-in macOS session with the Accessibility permission; it does not work from a plain ssh shell.
- Enterprise Grid, where the URL may carry an `E…` id, has not been observed.
- Slack updates often. A structural change makes commands fail with `ui_drift`; they do not guess.
- Between the final check and the send press there is a window of a few milliseconds in which a person could change Slack. The confirmation step reports what actually appeared.
