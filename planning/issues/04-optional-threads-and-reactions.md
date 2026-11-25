<!-- title: Optional: thread replies and reactions, where they can be targeted exactly -->

This issue is optional follow-up work outside the v0.1 milestone. It adds reading a thread, replying in a thread, and reacting to a message, but only for the paths that can be proven to act on the exact message requested. A path that cannot meet that bar is documented as not supported and is not built.

Depends on all three milestone issues. Use their types as they are: `UINode`, `Locators`, `SlackWindow.verify`, `Navigator`, `MessageReader`, `MessageText`, `Composer`, `Sender`, `RemoteError`. The hard boundaries in the foundation issue apply: Accessibility reads, attribute writes and `AXPress` only; no synthetic keyboard or mouse events; no Slack API; documented `slack://` links only.

## What is and is not known

Observed in Slack 4.53.292:

- Every rendered message item has `AXDOMIdentifier` `message-list_<ts>`, so a message can be found by its timestamp.
- A message that already has reactions carries a group with class `c-reaction_bar`. Each reaction in it is an `AXCheckBox` with subrole `AXToggleButton`, class `c-reaction`, the extra class `c-reaction--reacted` when the user has reacted, and it supports `AXPress`. The bar ends with an `AXButton` of class `c-reaction_add`.
- The hover toolbar that holds "reply in thread" and "add reaction" is absent from the tree while the message is neither hovered nor focused.
- Slack documents no `slack://` link for a message or a thread.

Never observed: an open thread pane, the web area URL while a thread is open, the reply-count control on a message that has replies, the hover toolbar after a message item receives `AXFocused`, the emoji picker, and how a reaction node identifies its emoji.

## Step 1: structural probe

Before any design, record the missing structure in `docs/validation/threads-reactions.md`. Work only in the disposable destination supplied in `SLACK_REMOTE_TEST_TEAM` and `SLACK_REMOTE_TEST_CHANNEL`; if it is not supplied, stop and report. Record roles, subroles, DOM classes and id shapes only, never text.

Seed the test conversation by hand: one message with a reply, one message with a reaction, one message with neither. Then record:

1. The reply-count control on the message that has a reply: role, classes, whether it supports `AXPress`.
2. After that control is pressed: the web area URL shape, the locator of the thread pane (expected to be a second `p-view_contents` group), the id shape of its message items, and whether it contains its own `ql-editor` and send button.
3. Whether any id in the thread pane, or the URL, contains the root message's timestamp.
4. On the message with neither: whether setting `AXFocused` to true on the message item makes the hover toolbar appear in the tree, and the classes of its buttons.
5. On a reaction node: which attribute, class or child identifies the emoji by its short name.
6. After `c-reaction_add` is pressed: the picker's container, its search field, the result items and how a result identifies its emoji by short name.

## Step 2: decide per feature

Apply these gates to the probe results. Record each decision and its reason in the validation file.

| Feature | Build it only if |
|---|---|
| Read a thread | The open thread can be tied to the requested root timestamp by an id or the URL, not by position or text. |
| Reply in a thread | The read gate holds, and the thread pane has exactly one editor and one send button that can be located inside the pane. |
| Open a thread on a message without replies | Setting `AXFocused` exposes a reply control that can be pressed. Otherwise replies are limited to messages that already have a thread. |
| Toggle an existing reaction | A reaction node identifies its emoji by short name exactly. |
| Add a new reaction | The picker's results identify their emoji by short name exactly, and the search field accepts an Accessibility write. |

## Contracts for the features that pass

All commands take the shared destination flags, require `--team` and `--channel`, and run preflight, lock, tree session, the human-in-use gate and `Navigator.navigate` as `send` does.

```
slack-remote read  --team … --channel … --thread <TS>
slack-remote reply --team … --channel … --thread <TS> --text <TEXT> [--allow-broadcast]
slack-remote react --team … --channel … --ts <TS> --emoji <SHORT_NAME>
```

`<TS>` matches `^\d{10}\.\d{6}$`. `<SHORT_NAME>` matches `^[a-z0-9_+'-]+$`, with no colons.

Shared targeting rules:

- The target message is the item whose `domID` equals `message-list_<TS>`. If it is not rendered, fail with `destination_unreachable`. Do not scroll to find it.
- A thread is "verified" when the conversation passes `SlackWindow.verify` and the thread pane is tied to `<TS>` by the id or URL evidence found in step 1. Add `verifyThread` beside `verify` and require it immediately before every write and press in the pane.
- `reply` reuses `Composer` and `Sender` with the pane as their scope: same text rules, same refusal of an existing draft, same final gate, same single press, same confirmation, with the new message looked up in the pane's list.
- `react` presses once and confirms by re-reading the target message: a reaction node for that short name exists with the reacted class. If the user had already reacted, succeed without pressing and report `alreadyReacted: true`. Never remove a reaction.
- When the picker is used, select a result only when its short name equals the request exactly. If the picker is still open at the end of a failed attempt, report `pickerLeftOpen: true`; do not try to dismiss it with key events.

Results follow the existing envelope. `read --thread` returns the same message shape as `read`, with `"scope": "rendered-thread"` and `"thread": "<TS>"`. `reply` returns the `send` result plus `"thread"`. `react` returns `{ "ts", "emoji", "reacted": true, "alreadyReacted": false }`.

## Files

Create:

```
Sources/slack-remote/Commands/Reply.swift
Sources/slack-remote/Commands/React.swift
Sources/SlackRemoteCore/ThreadView.swift
Sources/SlackRemoteCore/Reactions.swift
Tests/SlackRemoteCoreTests/ThreadViewTests.swift
Tests/SlackRemoteCoreTests/ReactionsTests.swift
Tests/SlackRemoteCoreTests/Support/ThreadFixtures.swift
docs/validation/threads-reactions.md
```

Modify: `Main.swift` (subcommand list), `Commands/Read.swift` (the `--thread` option), `Locators.swift` (a new "Threads and reactions" section), `Composer.swift` and `Sender.swift` only as far as needed to accept a scope other than the primary view, and `README.md`.

## Tests

Fixture trees for the structures recorded in step 1, then one test per rule: the target message is found by id; an unrendered target fails; a thread pane tied to a different root fails `verifyThread`; `reply` presses nothing when the pane changes before the press; `react` presses the matching reaction once; `react` on an already-reacted emoji presses nothing; a picker result with a different short name is not selected.

## Live validation

Only in the disposable destination, and only with `SLACK_REMOTE_TEST_ALLOW_SEND=1` for `reply` and `react`, since both change what other members see. Record in `docs/validation/threads-reactions.md`: the step 1 structure, the step 2 decisions, and for each built command one successful run and one refused run with the exit status.

## Acceptance criteria

- The validation file contains the probe results and a decision with a reason for each of the five features.
- Each built command acts only after the conversation and the message or thread were verified by id immediately beforehand.
- `reply` and `react` press at most once per invocation.
- `react` never removes a reaction.
- A feature that failed its gate has no command, and `README.md` lists it as not supported with the reason.
- `swift build -c release` and `swift test` succeed, and the package still contains no `CGEvent` use, no AppleScript and no pasteboard access.
