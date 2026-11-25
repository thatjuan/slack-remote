<!-- title: Read the messages Slack has rendered in a conversation -->

Add `slack-remote read`, which returns the messages currently rendered in a conversation's message list as JSON. It reads through macOS Accessibility only. It does not scroll, load history, or call any Slack API.

Depends on the foundation issue ("Foundation: Swift package, Accessibility session, safety gates, and the doctor, current and open commands"). Use its `UINode`, `Locators`, `SlackWindow.verify`, `Navigator`, `RemoteError`, output envelope and test fixtures as they are. The hard boundaries listed there apply here.

## Files

Create:

```
Sources/slack-remote/Commands/Read.swift
Sources/SlackRemoteCore/MessageReader.swift
Tests/SlackRemoteCoreTests/MessageReaderTests.swift
Tests/SlackRemoteCoreTests/Support/MessageFixtures.swift
docs/validation/read.md
```

Modify only:

- `Sources/slack-remote/Main.swift`: add `Read` to the subcommand list.
- `Sources/SlackRemoteCore/Locators.swift`: the "Messages" section only, and only to correct a constant that live validation proves wrong.
- `README.md`: add a `read` section.

## What was observed on the real client

Structure of a conversation in Slack 4.53.292, recorded without reading any text:

- The primary view contains one `AXList` with subrole `AXContentList`: the message list.
- Its children are `AXGroup` nodes with class `c-virtual_list__item`.
- A message item has `AXDOMIdentifier` of the form `message-list_<10 digits>.<6 digits>`. The digits are the Slack message timestamp, which identifies the message within its conversation.
- Other items are day dividers and spacers, with ids such as `message-list_<13 digits>…divider` and `message-list_bottomSpacer`.
- Inside a message item is one `AXGroup` with subrole `AXDocument` and class `c-message_kit__hover`.
- The sender is an `AXButton` with class `c-message__sender_button`. Slack omits it on consecutive messages from the same sender.
- Body text sits under `AXGroup` nodes with class `p-rich_text_section`, as `AXStaticText` nodes and as `AXLink` nodes that contain `AXStaticText`.
- Attachments sit under nodes whose classes begin with `c-message_attachment`.
- Existing reactions are `AXCheckBox` nodes with subrole `AXToggleButton` and class `c-reaction`, with the extra class `c-reaction--reacted` when the user has reacted.
- The list is virtualised. It holds the messages on screen and a small buffer around them.

Not yet observed: the `AXValue` of text nodes, how emoji inside text are exposed, the label on a reaction, and messages made of blocks from apps. The live validation below settles each one.

## Command

```
slack-remote read [--team <TEAM_ID> --channel <CONVERSATION_ID> [--user <USER_ID>] [--interrupt]] [--limit <N>]
```

- Without destination flags it reads the current conversation and never navigates. If the current view is not a conversation it fails with `slack_not_ready`.
- With `--team` and `--channel` it calls `Navigator.navigate`, which verifies the destination, and then reads. Passing one of the two without the other is an argument error.
- `--limit` keeps the newest N messages. Default: every rendered message.

Result:

```json
{
  "ok": true, "command": "read", "slackVersion": "4.53.292", "warnings": [],
  "result": {
    "team": "T0AAAAAAA",
    "conversation": "C0BBBBBBB",
    "route": "already_there",
    "scope": "rendered",
    "skippedItems": 0,
    "messages": [
      {
        "ts": "1700000000.000100",
        "sender": "Ada",
        "senderInherited": false,
        "text": "Deploy is done.\nLogs look clean.",
        "hasAttachments": false,
        "reactions": [ { "label": "…", "reacted": true } ]
      }
    ]
  }
}
```

`scope` is always `"rendered"`. It tells the caller that the result is what Slack has drawn, not the conversation's history.

## Extraction rules

`MessageReader` is a pure function over a `VerifiedView`:

```swift
public struct Message: Encodable, Equatable {
    public let ts: String
    public let sender: String?
    public let senderInherited: Bool
    public let text: String
    public let hasAttachments: Bool
    public let reactions: [Reaction]
}
public struct Reaction: Encodable, Equatable { public let label: String; public let reacted: Bool }

public enum MessageReader {
    public static func read(_ view: VerifiedView, limit: Int?) throws -> (messages: [Message], skippedItems: Int)
}
```

1. Find exactly one `messageList` inside the primary view. Zero or several is `ui_drift`.
2. Take its `messageItem` children in tree order, which is oldest first.
3. `ts`: match the item's `domID` against `^message-list_(\d{10}\.\d{6})$`. An item that does not match is a divider or spacer and is ignored without counting.
4. An item that matches but does not contain exactly one `messageBody` is counted in `skippedItems` and left out.
5. `sender`: the `AXTitle` of the `senderButton` inside the message body. If there is none, copy the sender of the previous message in the list and set `senderInherited` to true. If there is no previous message, `sender` is null and `senderInherited` is false.
6. `text`: for each `richTextSection` inside the message body, in document order, concatenate the `AXValue` of every `AXStaticText` descendant. Join the sections with `"\n"`. A message with no rich text section has `text` equal to `""`.
7. `hasAttachments`: true when any descendant has a class beginning with `c-message_attachment`.
8. `reactions`: one entry per `reaction` node. `label` is its `AXTitle`, or its `AXDescription` when the title is empty. `reacted` is whether it has the class `c-reaction--reacted`.
9. Apply `limit` last, keeping the newest.

An empty conversation yields an empty `messages` array and exit status 0.

Decide rule 6 for emoji during live validation. If emoji inside text are `AXImage` nodes with a title such as `:tada:`, include that title in place, in document order, and add a fixture test for it. If they carry no title, leave them out and say so in `docs/validation/read.md`.

## Privacy

Message text and sender names go to stdout as the command result and nowhere else. `--debug` prints locator names, counts and timings only. Tests and documentation use invented content.

## Tests

`MessageFixtures.swift` adds helpers that append message items to the `SlackFixture` window: a message with sender and sections, a message without a sender button, a divider, a message with an attachment node, a message with reaction nodes.

Write these tests in `MessageReaderTests` and no others:

- One message with a sender and two rich text sections produces the joined text.
- Text inside a link within a section is included in order.
- A message without a sender button inherits the previous sender and is flagged; the first message without one has a null sender.
- Dividers and spacers are ignored and not counted.
- A matching item with no message body is counted in `skippedItems`.
- Reactions report label and `reacted`.
- An attachment node sets `hasAttachments`.
- `limit` keeps the newest N in order.
- Two message lists in the primary view throw `ui_drift`.

## Live validation

Write results to `docs/validation/read.md`. Record counts and field coverage only. Do not paste message text, names or ids from a real workspace into the file or the pull request.

Allowed on any workspace, because `read` without destination flags only reads:

1. Open a conversation by hand and run `slack-remote read`. Compare with the screen: the newest message's text matches, the count is plausible for what is rendered, and consecutive messages from one sender show the inherited sender.
2. Check a message with a link, one with emoji, one with a reaction, one with an attachment and one posted by an app. Record for each whether `text`, `reactions` and `hasAttachments` were right. Record the shape of a reaction `label`, for example "count, emoji name", without the actual content.
3. Record `skippedItems` and investigate any value above zero.
4. Confirm the conversation on screen, the scroll position and the frontmost application are unchanged afterwards.

Allowed only against the disposable destination supplied in `SLACK_REMOTE_TEST_TEAM` and `SLACK_REMOTE_TEST_CHANNEL`. If they are not set, skip this step and say so in the pull request.

5. From another conversation, run `read --team … --channel …` and confirm `route` shows a navigation and the messages belong to the test conversation.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- `read` returns the envelope and fields above, oldest message first.
- `read` without destination flags never changes the conversation, the scroll position or the frontmost application.
- `read` with destination flags returns messages only after `SlackWindow.verify` has passed for that destination.
- Every `ts` in the result matches `^\d{10}\.\d{6}$`.
- No message text or sender name is written anywhere except stdout.
- `README.md` documents the command, the meaning of `scope: "rendered"`, and one example.
- `docs/validation/read.md` records the live validation steps that were run, their outcomes, and which were skipped and why.
