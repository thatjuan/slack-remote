<!-- title: Thread read and reply, reactions, and emoji in messages -->
<!-- replaces the body of the issue filed as "Optional: thread replies and reactions, where they can be targeted exactly" -->

This issue was filed as optional because no route to a thread or a reaction had been observed. A second probe found one, so it is now required work in the v1.0 milestone. It adds `read --thread`, `reply`, `react`, and `:short_name:` emoji in message text.

Depends on issues 1, 2, 3 and 5. Use their types as they are: `UINode`, `Locators`, `SlackWindow.verify`, `Navigator`, `MessageReader`, `MessageText`, `Composer`, `Sender`, `Overlays`, `VirtualListPager`, `Account`, `RemoteError`. The hard boundaries from issue 1 apply: Accessibility reads, attribute writes and semantic actions only; no synthetic keyboard or mouse events; no coordinate-based clicks; no Slack API.

## What was observed on the real client

Slack 4.53.292, structure only, in the two designated test conversations. Nothing was sent or reacted to.

Targeting a message:

- Every rendered message item has the id `message-list_<TS>`.
- The action `AXShowMenu` on a message item opens the "Message actions" menu: an `AXMenu` with class `c-menu__items` inside a `ReactModal__Content` popup. While it is open, that message item carries the class `c-virtual_list__item--contextmenu-visible`.
- Menu items are `AXMenuItem` nodes with `AXPress`. The two this issue uses have the classes `p-message_actions_menu__comment` (reply in thread) and `p-message_actions_menu__add_reaction`.
- `AXPress` on the node with class `ReactModal__Overlay` closes the menu. `AXCancel` does not.
- Setting `AXFocused` on a message does not reveal the hover toolbar. The menu is the route.

Thread pane:

- It is the `AXGroup` with classes `p-view_contents p-view_contents--secondary`.
- The web area URL does not change when a thread opens.
- Its list items have ids `<CONVERSATION_ID>-<ROOT_TS>-thread-list-Thread_<TS>`. The composer row's id ends `-thread-list-Thread_input`.
- It contains exactly one `ql-editor` text area and one send button, located the same way as in the primary view.
- A checkbox with class `c-input_checkbox` and id `p-thread_footer__broadcast_checkbox--<CONVERSATION_ID>-<ROOT_TS>--Thread` also sends the reply to the channel.
- The `AXButton` with class `p-flexpane_header__control` inside the pane's `p-flexpane_header` toolbar closes the pane. A second control with that class is an `AXPopUpButton` and must not be pressed.

Emoji picker:

- It is an `AXGroup` with class `p-emoji_picker` inside a `ReactModal__Content` popup.
- Each emoji is an `AXCell` with class `p-emoji_picker__list_item`, action `AXPress`, and id `emoji-picker-<short_name>`.
- The search field is an `AXTextField` with class `p-emoji_picker__input` and a settable `AXValue`. The grid is virtualised.
- `AXPress` on the overlay closes the picker.

Existing reactions: each is an `AXCheckBox` with class `c-reaction`, plus `c-reaction--reacted` when the user has reacted, inside a group with class `c-reaction_bar`.

## Step 1: three observations

Use `slack-remote inspect` and the `notes` destination. Seed it by hand first: one message with a reply, one with a reaction of your own, one containing an emoji in its text. Record the answers in `docs/validation/threads-reactions.md`.

1. A thread with replies: confirm the root is the item ending `Thread_<ROOT_TS>` and replies follow in order.
2. A reaction node: find what names its emoji. Candidates are a child `AXImage` with class `c-emoji`, and the node's own attributes. Extend `inspect` with a `--emoji-names` flag that prints, for `c-emoji` images only, the title when it matches `^:[a-z0-9_+'-]+:$`. If no attribute yields the short name, rule R2 below applies.
3. Emoji in text: the same question for a `c-emoji` image inside `p-rich_text_section`, and what the composer's `AXValue` reads back after issue 3's write method inserts `:tada:`.
4. The picker: set the search field's `AXValue` to `tada` and record whether the grid filters to cells whose ids contain it.

## Targeting rules

`MessageTarget.swift`:

```swift
/// Finds the item with id message-list_<ts> in the verified primary view.
/// When it is not rendered and `page` is true, pages toward the start with VirtualListPager
/// (bounds: 20 pages, the command deadline) until it is.
/// Throws message_not_rendered otherwise.
func locate(ts: String, in view: VerifiedView, page: Bool) throws -> any UINode

/// Opens the message menu for that item and returns it. Verifies that exactly one item carries
/// c-virtual_list__item--contextmenu-visible and that its id is message-list_<ts>.
func openMenu(ts: String, in view: VerifiedView, tree: SlackTree, deadline: Date) throws -> any UINode
```

If the menu opened for a different item, or two items carry the class, close the menu and throw `ui_drift`.

`ThreadView.swift`:

```swift
public struct VerifiedThread { public let destination: Destination; public let rootTs: String; public let pane: any UINode }

/// Passes only when: the conversation passes SlackWindow.verify; exactly one secondary view exists;
/// it has at least one list item; and every list item id starts with
/// "<conversation>-<rootTs>-thread-list-Thread_".
func verifyThread(_ destination: Destination, rootTs: String, in tree: SlackTree) throws -> VerifiedThread
```

Opening a thread: if `verifyThread` already passes, use it. If a different thread is open, close the pane with the close button and continue. Then `openMenu`, press `p-message_actions_menu__comment`, and poll `verifyThread` until the deadline. The menu closes itself when an item is pressed; confirm no modal remains.

## Commands

All take `--dest` or `--team` and `--channel`, and `--dry-run`. All run preflight, lock, tree session, the overlay check, the human-in-use gate, `Navigator.navigate` and `Account.verify`, as `send` does.

### `read --thread <TS>`

Opens and verifies the thread, then runs `MessageReader` over the pane's list with the id pattern `-thread-list-Thread_(\d{10}\.\d{6})$`. The result has `"scope": "rendered-thread"`, `"thread": "<TS>"`, and the usual `complete`, `stopReason` and `pages` fields. With `--history`, page the pane's list with `VirtualListPager`. The pane is left open; add `--close-thread` to close it afterwards.

### `reply --thread <TS> --text <TEXT> [--also-send-to-channel] [--allow-broadcast]`

`Composer` and `Sender` gain a scope parameter: the primary view, or a `VerifiedThread`'s pane. Everything in issue 3 holds inside that scope: text rules, refusal of an existing draft, read-back, the final gate, one press, confirmation.

Additions to the final gate:

- `verifyThread` passes again for the same conversation and root.
- The broadcast checkbox's checked state equals `--also-send-to-channel`. When it does not, press the checkbox once and re-read it; if it still differs, stop with `draftLeft: true`.

Confirmation looks for a new item in the pane whose timestamp is later than the newest one seen before the press and whose collapsed text equals the input. The result is the `send` result plus `"thread": "<TS>"`.

### `react --ts <TS> --emoji <SHORT_NAME> [--thread <ROOT_TS>]`

`<SHORT_NAME>` matches `^[a-z0-9_+'-]+$`. With `--thread`, the target is an item in the verified thread pane.

1. `locate` the message.
2. R1: if the message has a reaction node that names this emoji and carries `c-reaction--reacted`, return `"alreadyReacted": true` without pressing anything.
3. R2: if reaction nodes do not name their emoji (step 1 found no attribute), refuse whenever the message has any `c-reaction--reacted` node, with `ui_drift` and a message saying the tool cannot tell which emoji it would toggle. A second press on an emoji the user already used removes the reaction, and this command never removes one.
4. Inside `Overlays.withModal`: `openMenu`, press `p-message_actions_menu__add_reaction`, wait for exactly one `p-emoji_picker`.
5. Find the cell whose id equals `emoji-picker-<SHORT_NAME>` exactly. If it is not rendered, set the search field's `AXValue` to the short name and poll up to 2 s for the cell. If it never appears, close the picker and fail with `unsafe_text` and reason `unknown emoji`.
6. Final gate: `SlackWindow.verify` (and `verifyThread` when applicable), the picker is still the only modal, exactly one cell has that id. Press it once.
7. Confirm: the picker closes, and the target message gains a `c-reaction--reacted` node, which names the emoji when names are available. Otherwise fail with `reaction_unconfirmed` and do not retry.

Result: `{ "ts", "emoji", "reacted": true, "alreadyReacted": false }`.

### Emoji in message text

- Reading: `MessageReader` emits `:short_name:` in place for each `c-emoji` image inside rich text, using the attribute found in step 1. If none is available it emits nothing for the image and sets `"emojiOmitted": true` on that message.
- Writing: `send`, `draft set` and `reply` accept `:short_name:` and Unicode emoji in `--text`. The text rules gain one refusal: a `:name:` token whose name does not match `^[a-z0-9_+'-]+$`.
- Comparison: `MessageText.normalize` maps a Unicode emoji and its `:short_name:` to the same form only if step 1 shows the composer converts between them; record the mapping in the validation file. The read-back gate and the send confirmation otherwise compare literally, and a mismatch stops before sending, as in issue 3.

## Files

Replace the stubs `Sources/slack-remote/Commands/{Reply,React}.swift`.

Create: `Sources/SlackRemoteCore/{MessageTarget,ThreadView,Reactions}.swift`, `Sources/SlackRemoteCore/Locators+Threads.swift`, `Tests/SlackRemoteCoreTests/{MessageTarget,ThreadView,Reactions}Tests.swift`, `Tests/SlackRemoteCoreTests/Support/ThreadFixtures.swift`, `docs/commands/{reply,react}.md`, `docs/validation/threads-reactions.md`.

Modify: `Commands/Read.swift` (`--thread`, `--close-thread`), `Composer.swift` and `Sender.swift` (scope parameter, broadcast gate), `MessageReader.swift` and `MessageText.swift` (emoji), `Inspector.swift` (`--emoji-names`), their tests, and `docs/commands/{read,send}.md`. No other issue in this wave touches these files.

## Tests

- `MessageTargetTests`: found by id; not rendered throws `message_not_rendered`; paging finds an older message; a menu that opens for another item is closed and throws.
- `ThreadViewTests`: a pane for the right root passes; a pane for another root or another conversation fails; an empty pane fails.
- Reply, using the scripted composer from issue 3 inside a pane fixture: the happy path presses send once; the pane changing root before the press presses nothing; a checked broadcast box without the flag is unchecked before the press; a box that will not change stops with the draft left.
- `ReactionsTests`: R1 returns `alreadyReacted`; R2 refuses; the exact cell is pressed once; a cell for a longer name containing the short name is never pressed; an unknown emoji closes the picker and fails; no confirmation gives `reaction_unconfirmed`.
- `MessageReader` emoji: an image with a short name appears in place; one without sets `emojiOmitted`.

## Live validation

Only in the `notes` and `self` destinations, with synthetic text that starts `slack-remote test`. If a destination's composer or thread composer already holds a draft, skip the writing steps there and report it; never clear a draft the tests did not create. Record outcomes in `docs/validation/threads-reactions.md` without ids, names or message text.

1. The four observations in step 1.
2. `read --thread` on the seeded thread: root first, replies in order, pane verified.
3. `reply --dry-run`, then `reply` with a unique test string: exactly one reply appears in that thread and not in the channel.
4. `reply` on a message with no replies yet: a thread is started under the right message.
5. `reply` while a different thread is open in the pane: the tool switches threads and the reply lands in the requested one.
6. `react --emoji tada` on a test message: one reaction appears. Run it again: `alreadyReacted: true` and the reaction is still there.
7. `react` with a short name that does not exist: failure, picker closed, no reaction added.
8. `send --dest self --text "slack-remote test :tada:"`, then `read`: the emoji comes back as `:tada:`.
9. After every step: no popup left open, and the conversation shown is the test destination.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- A reply or reaction happens only after the conversation, and the message or thread, were verified by id immediately before the press.
- `reply` and `react` press their final control at most once per invocation, and `react` never removes a reaction.
- A thread is identified by the conversation id and root timestamp in its item ids, never by position or text.
- No popup opened by a command is left open without `overlay_left_open` being reported.
- Emoji in text survive a `send` then `read` round trip in the form documented in `docs/commands/send.md`.
- The validation file records the four observations and the outcome of each live step.
