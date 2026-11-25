<!-- title: Write a draft and send a message to a verified conversation -->

Add three commands: `draft set` puts text into a conversation's composer and stops, `draft clear` removes a draft the caller can name exactly, and `send` posts a message. Each one acts only on a conversation whose team and conversation ids were verified immediately before the action, and each one stops without acting when anything is unexpected.

Depends on the foundation issue ("Foundation: Swift package, Accessibility session, safety gates, and the doctor, current and open commands") and the read issue ("Read the messages Slack has rendered in a conversation"). Use their types as they are: `UINode`, `Locators`, `SlackWindow.verify`, `VerifiedView`, `Navigator`, `MessageReader`, `RemoteError` and the output envelope. The hard boundaries in the foundation issue apply here: Accessibility attribute writes and `AXPress` only, no synthetic keyboard or mouse events, no clipboard tricks, no Slack API.

## Files

Create:

```
Sources/slack-remote/Commands/Draft.swift
Sources/slack-remote/Commands/Send.swift
Sources/SlackRemoteCore/MessageText.swift
Sources/SlackRemoteCore/Composer.swift
Sources/SlackRemoteCore/Sender.swift
Tests/SlackRemoteCoreTests/MessageTextTests.swift
Tests/SlackRemoteCoreTests/ComposerTests.swift
Tests/SlackRemoteCoreTests/SenderTests.swift
Tests/SlackRemoteCoreTests/Support/ComposerFixtures.swift
docs/validation/write.md
```

Modify only:

- `Sources/slack-remote/Main.swift`: add `Draft` and `Send` to the subcommand list.
- `Sources/SlackRemoteCore/Locators.swift`: the "Composer" section only, and only to correct a constant that live validation proves wrong.
- `README.md`: add `draft` and `send` sections.

## What was observed on the real client

Structure of the composer in Slack 4.53.292, recorded without typing anything:

- The primary view contains exactly one `AXTextArea` with class `ql-editor`: the message editor.
- An empty editor also has the class `ql-blank`.
- The editor reports `AXValue`, `AXFocused`, `AXSelectedText` and `AXSelectedTextRange` as settable.
- The primary view contains exactly one `AXButton` with class `c-wysiwyg_container__button--send`. With an empty editor it also has the class `c-button--disabled` and `AXEnabled` is false. It supports `AXPress`.
- A separate pop-up button with class `c-wysiwyg_container__button--send_options` schedules messages. This issue never touches it.
- A conversation that holds a draft shows the class `p-channel_sidebar__channel--draft` on the group inside its sidebar row.

Not yet observed, and the reason this issue starts with a spike: which attribute write puts text into the editor, what `AXValue` reads back afterwards, whether Slack saves text written this way as a draft, and what the tree looks like after `AXPress` on the send button.

## Step 1: write-method spike

Do this before writing the commands, against the disposable destination only (see "Live validation" for how it is supplied). If no disposable destination is supplied, stop and report; do not experiment in any other conversation.

With a small throwaway executable or a debug subcommand that is removed before the pull request, and an empty composer in the disposable destination, find out:

1. Method A: set `AXFocused` to true on the editor, then set `AXSelectedText` to the text. Does the text appear, does `ql-blank` go away, does the send button become enabled?
2. Method B: set `AXValue` to the text. Same three questions.
3. What does the editor's `AXValue` read back for: one line of plain text; two lines separated by `\n`; text containing a URL; text containing `*stars*` and `:tada:`? Record whether the read-back equals the input after the normalisation defined below.
4. Clearing: with text present, set `AXSelectedTextRange` to cover the whole value and set `AXSelectedText` to `""`; separately, set `AXValue` to `""`. Which returns the editor to `ql-blank` with the send button disabled?
5. Do methods A and B work when Slack is not the frontmost application?

Record the answers in `docs/validation/write.md`. Then build `Composer` to try the working methods in the fixed order A, B. If neither method works, stop and report on the issue with what was observed. Do not substitute key events, pasteboard paste, or any other input path.

## Text rules

`MessageText.validate(_:allowBroadcast:)` runs before anything touches Slack and throws `unsafe_text` with a reason:

- Empty or whitespace-only text.
- More than 4000 characters.
- Control characters other than `\n` and `\t`.
- First non-whitespace character is `/`. Slack would run it as a slash command.
- The whole text matches `^\+:[^:\s]+:\s*$`. Slack would add a reaction to the previous message.
- Contains `@channel`, `@here` or `@everyone` in any letter case, unless `allowBroadcast` is true.

`MessageText.normalize(_:)` is used on both sides of every comparison: convert `\r\n` to `\n`, apply Unicode NFC, and remove one trailing `\n` if present. If the spike shows the editor returns a different whitespace representation, such as a no-break space for a space, add that single mapping here and document it. Never fold case or punctuation.

## Composer

```swift
public enum ComposerState: Equatable {
    case empty
    case text(String)        // normalised
    case pendingContent      // blank editor but send enabled, e.g. an attached file
}

public struct Composer {
    public init(view: VerifiedView)
    public func state() throws -> ComposerState
    public func write(_ text: String, deadline: Date) throws -> WriteMethod   // selected_text, value, existing
    public func clear(expecting text: String, deadline: Date) throws
}
```

`Composer` resolves `composerEditor` and `sendButton` with `one(_:)` inside the primary view of the `VerifiedView`. Zero or several of either is `ui_drift`.

State:

- `empty`: the editor has class `ql-blank` and the send button is disabled (has `c-button--disabled`, or `AXEnabled` is false).
- `pendingContent`: the editor has `ql-blank` and the send button is enabled.
- `text(t)`: otherwise, where `t` is the normalised `AXValue` of the editor.

`write(text)`:

1. Read the state.
   - `text(t)` with `t` equal to the normalised input: return `existing` without writing. This makes a retry after a failure safe.
   - `text` with anything else, or `pendingContent`: throw `draft_conflict`. Details carry `existingLength` only, never the existing text. An existing draft is never replaced, appended to or cleared.
2. Try method A. Poll every 100 ms for up to 2 s for the state to become `text` equal to the normalised input.
3. If the state is still `empty`, try method B and poll the same way.
4. If the state is `text` and differs from the input, stop: throw `write_unverified` with `draftLeft: true`. Do not try the other method and do not clear.
5. If the state is still `empty` after both methods, throw `write_failed` with `draftLeft: false`.

`clear(expecting:)`:

1. The state must be `text(t)` with `t` equal to the normalised expected text. Anything else throws `draft_conflict`. `empty` is success with nothing to do.
2. Clear with the method the spike found, and poll up to 2 s for `empty`. Otherwise throw `write_unverified` with `draftLeft: true`.

## Blocking dialogs

Before any composer write and before the send press, search the verified window's web area for a node whose subrole is `AXApplicationDialog` or `AXApplicationAlertDialog`, or whose role is `AXSheet`. If one exists, throw `ui_blocked`. This rule comes from how Chromium maps dialogs to Accessibility and has not been observed in Slack; during live validation open Slack's Preferences by hand, run `draft set`, and record whether the gate fires. Correct the rule if Slack's dialogs use a different subrole.

## Commands

All three take the shared destination flags. `--team` and `--channel` are required: a write never targets "wherever Slack is".

```
slack-remote draft set   --team <TEAM_ID> --channel <CONVERSATION_ID> [--user <USER_ID>] [--interrupt] --text <TEXT>
slack-remote draft clear --team <TEAM_ID> --channel <CONVERSATION_ID> [--user <USER_ID>] [--interrupt] --expect-text <TEXT>
slack-remote send        --team <TEAM_ID> --channel <CONVERSATION_ID> [--user <USER_ID>] [--interrupt] --text <TEXT> [--allow-broadcast]
```

Order of work for each command:

1. Validate the text. Nothing else happens if it is refused.
2. Preflight, lock, tree session, as in the foundation.
3. Human-in-use gate. These commands change focus inside Slack, so the gate applies even when no navigation is needed. If Slack is frontmost and the user gave input in the last 30 s, fail with `slack_in_use` unless `--interrupt` is passed.
4. `Navigator.navigate` to the destination, which verifies it.
5. The command's own steps below.

### `draft set`

Check for a blocking dialog, then `Composer.write`. It never presses send.

```json
{ "ok": true, "command": "draft set", "slackVersion": "4.53.292", "warnings": [],
  "result": { "team": "T0AAAAAAA", "conversation": "C0BBBBBBB", "route": "deep_link_channel", "method": "selected_text", "length": 31 } }
```

### `draft clear`

Check for a blocking dialog, then `Composer.clear(expecting:)`.

```json
{ "ok": true, "command": "draft clear", "slackVersion": "4.53.292", "warnings": [],
  "result": { "team": "T0AAAAAAA", "conversation": "C0BBBBBBB", "route": "already_there", "cleared": true } }
```

`cleared` is false when the composer was already empty.

### `send`

`Sender.send` runs these steps:

1. Check for a blocking dialog, then `Composer.write` (which may return `existing`).
2. Read the newest rendered message timestamp with `MessageReader`: `lastTs`, or nil when the list is empty.
3. Final gate. Refresh the tree from the window root and, with no waiting between the checks:
   - run `SlackWindow.verify` for the destination again;
   - check for a blocking dialog again;
   - build a new `Composer` from the fresh view and require its state to be `text` equal to the normalised input;
   - require exactly one `sendButton`, enabled.

   Any failure throws its own error with `draftLeft: true`, and send is not pressed.
4. `perform(.press)` on the send button, once. Never press twice and never retry.
5. Confirm. Poll every 100 ms until the deadline for both: the composer state is `empty`, and `MessageReader` returns a message whose `ts` is greater than `lastTs` (or any message when `lastTs` is nil) and whose text matches the input. For this comparison only, use `MessageText.collapse(_:)` on both sides: normalise, then replace every run of whitespace with one space and trim. Slack may render line breaks differently from how the composer holds them, and the message is already sent at this point, so the match tolerates whitespace layout and nothing else.
   - Both hold: success with that `ts`.
   - Composer still holds the text at the deadline: throw `send_not_performed` with `draftLeft: true`.
   - Composer is empty but no matching message appeared: throw `send_unconfirmed`. The message may have been sent. The error message must tell the caller to check the conversation and not to retry blindly.

Compare timestamps as strings split on `.` into two integers.

```json
{ "ok": true, "command": "send", "slackVersion": "4.53.292", "warnings": [],
  "result": { "team": "T0AAAAAAA", "conversation": "C0BBBBBBB", "route": "deep_link_channel", "method": "selected_text", "sent": true, "ts": "1700000000.000200" } }
```

The final gate exists because a person or another program can change Slack between the write and the press. Re-reading the web area URL, the sidebar selection and the composer text right before the press reduces that window to a few milliseconds. The confirmation step then reports honestly when the outcome cannot be established.

## Failure and recovery

- A failure before the write leaves Slack untouched.
- A failure after the write leaves the text in the verified destination's composer as a draft and says so with `draftLeft: true`. The tool does not clean up automatically, because a second write in an unexpected state is a second risk.
- The caller recovers by running the same `send` again, which finds the identical text and continues, or by running `draft clear --expect-text` with the same text.
- `send_unconfirmed` is terminal for the tool. The caller decides after checking with `read`.

## Tests

`ComposerFixtures.swift` adds a scripted composer to the `SlackFixture` window: setting `selectedText` or `value` on the fake editor can be configured to update its value, drop `ql-blank` and enable the send button; pressing the fake send button can be configured to blank the editor and append a message item with a later timestamp.

Write these tests and no others:

- `MessageTextTests`: one case per refusal rule; `--allow-broadcast` permits `@here`; normalisation of `\r\n`, a trailing newline and a decomposed accent; `collapse` treats a line break and a space as equal and keeps a changed word unequal.
- `ComposerTests`: empty, text and pending states; method A succeeds; method A does nothing and method B succeeds; a different existing draft throws `draft_conflict` and nothing is written; an identical existing draft returns `existing`; a read-back that differs throws `write_unverified` and no second method is tried; neither method works throws `write_failed`; `clear` refuses a draft that differs from the expected text.
- `SenderTests`: the happy path returns the new `ts` and presses send exactly once; the conversation changing between write and press throws `destination_mismatch` with no press; the composer text changing between write and press throws with no press; a disabled send button at the gate throws with no press; a dialog node throws `ui_blocked` with no press; the composer staying full after the press throws `send_not_performed`; the composer emptying with no matching message throws `send_unconfirmed`; a message from someone else arriving with different text does not confirm the send.

## Live validation

Write results to `docs/validation/write.md`. Record outcomes and methods only, never message text from a real conversation.

Every step here writes to Slack, so every step is limited to the disposable destination. It is supplied in `SLACK_REMOTE_TEST_TEAM` and `SLACK_REMOTE_TEST_CHANNEL`, with a second conversation in `SLACK_REMOTE_TEST_CHANNEL_2` for the persistence step. Live sending needs `SLACK_REMOTE_TEST_ALLOW_SEND=1` as well. Without the first two variables, run no live step at all. Without the send variable, run the draft steps and skip the send steps. In both cases say so in the pull request. Never choose a destination yourself and never send to a real workspace conversation.

Draft steps:

1. The spike in step 1 of this issue.
2. `draft set` with a unique test string, then confirm on screen that the text is in the test conversation's composer and nothing was sent.
3. Persistence: `open` the second test conversation, confirm the first one's sidebar row shows the draft class, `open` the first again and confirm `draft set` with the same text returns `method: "existing"`.
4. `draft set` with different text while that draft exists: `draft_conflict`, exit status 15, composer unchanged.
5. `draft clear --expect-text` with the wrong text: `draft_conflict`. With the right text: composer empty, `cleared: true`.
6. `draft set` with each refused text form: `unsafe_text`, and Slack is not touched.
7. `draft set` with Slack in the background and another application frontmost. Record whether it works and whether focus moved.
8. Run `draft set` while typing in Slack: `slack_in_use`, exit status 14.

Send steps, only with `SLACK_REMOTE_TEST_ALLOW_SEND=1`:

9. `send` a unique test string. Confirm one message appeared in the test conversation, the returned `ts` matches `read`, and the composer is empty.
10. `send` a two-line message. Record whether it sent as one message or was refused at read-back.
11. With a draft left by step 2, run `send` with the same text and confirm it resumes with `method: "existing"`.
12. Start a `send` and, from a second terminal, run `open` to the other test conversation with `--timeout 30`. Confirm the lock makes the second command wait and the message lands only in the first conversation.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- Nothing is written to Slack unless `SlackWindow.verify` passed for the requested team and conversation ids immediately beforehand.
- `send` presses the send button at most once per invocation, and only after the final gate passed.
- An existing draft that differs from the requested text is never modified by any command.
- `draft clear` removes only text that equals `--expect-text` after normalisation.
- Text refused by the text rules never reaches Slack.
- Every failure after a write reports `draftLeft` truthfully.
- No test and no validation step sends or drafts in a conversation other than the disposable destination.
- The package still contains no `CGEvent` use, no AppleScript and no pasteboard access.
- `README.md` documents the three commands, the text rules, the recovery procedure and the meaning of `send_unconfirmed`.
- `docs/validation/write.md` records the spike answers, which live steps ran with their outcomes, and which were skipped and why.
