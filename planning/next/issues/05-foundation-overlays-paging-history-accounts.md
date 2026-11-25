<!-- title: v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run -->

> Plan labels used in this text. Issues 1 to 3 are the v0.1 issues: foundation with `doctor`, `current` and `open`; `read`; `draft` and `send`. Issue 4 is "Thread read and reply, reactions, and emoji in messages". Issue 5 is "v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run". Issue 6 is "List channels, conversation members and the people directory". Issue 7 is "Native Slack search: messages, files and other result types, with filters and navigation to a result". Issue 8 is "Upload a file to a verified channel, DM or thread". Issue 9 is "Installable v1.0 release and the full validation matrix on main-mac". GitHub numbers may differ from these labels.

The v0.1 milestone delivered `doctor`, `current`, `open`, `read`, `draft` and `send`. This issue adds the shared machinery the rest of v1.0 needs, and the first features built on it: reading history beyond what is rendered, verifying which Slack account is signed in, named destinations, and `--dry-run`. Four later issues (threads and reactions, listing, search, upload) run after this one and depend on the names defined here.

Depends on issues 1, 2 and 3 being merged. Use their types as they are. The hard boundaries from issue 1 still apply: documented `slack://` links and macOS Accessibility reads, attribute writes and semantic actions only. No Slack API, no tokens, no injection, no synthetic mouse or keyboard events, no coordinate-based clicks, no CI workflows.

## Apply the amendments first

`planning/next/amendments-to-1-3.md` lists four corrections to issues 1 to 3 that came from observing the real client. Check each against the merged code and apply any that is missing, with its test:

1. The sidebar route presses the `p-channel_sidebar__channel` group inside the row.
2. `slack://channel` is the route for every conversation id unless `--user` selects `slack://user`; `--route sidebar` forces the sidebar route.
3. Tree readiness requires a parseable client URL, and `SlackTree.refresh()` throws `tree_unavailable` when the tree is gone.
4. A blocking dialog is a node with class `ReactModal__Content` or role `AXSheet`, checked before destination verification.

## What was observed on the real client

Slack 4.53.292, structure only:

- Performing `AXScrollToVisible` on the oldest rendered message item makes Slack render older messages. Three rounds took the set of seen message ids from 3 to 16 while the list dropped items at the other end.
- Every Slack popup is a node with class `ReactModal__Content`. While one is open, `p-view_contents--primary` is absent from the tree. `AXPress` on the node with class `ReactModal__Overlay` closed the message menu, the emoji picker, the details modal and, once its field was empty, the search modal. `AXCancel` returns success and closes nothing.
- The search modal opens from the `AXButton` with class `p-top_nav__search`. It contains `AXCheckBox` quick filters; the one whose id starts with `quick-filter-from-` ends with the signed-in user's id.
- The self-DM is the one sidebar row containing the class `p-channel_sidebar__channel--im-you`; its id is the self-DM's conversation id.
- A second process that clears `AXManualAccessibility` removes the tree under a running command.

Not observed: how the start of a conversation appears in the message list. Step 1 below settles it.

## Step 1: `inspect`, then one observation

Build `inspect` first; every later spike in v1.0 uses it in place of ad-hoc probe programs.

```
slack-remote inspect [--scope window|primary|secondary|modal|sheet] [--max-depth <N>]
```

It runs preflight, lock and tree session like any command, then prints one line per node: indentation, role, subrole, DOM classes, DOM id, action names, and which of `AXValue`, `AXFocused`, `AXSelectedText` are settable. It never reads or prints titles, descriptions, values or URLs. In ids and classes it masks every run matching `[A-Z][A-Z0-9]{7,}` or `[0-9]{6,}` as the first character, `§`, and the run's length, so `C0BBBBBBB` prints as `C§9`. It does not descend into `AXTextArea` or `AXComboBox` nodes. Output is plain text on stdout, the one exception to JSON output.

Then, in the `self` destination (see "Live validation"), page to the start of the conversation with the pager below and use `inspect --scope primary` to record what the list contains above the first message. Write the finding to `docs/validation/v1-foundation.md`. If a distinct node marks the start, add it to `Locators.swift` as `conversationStart` and use it as the end marker for history. If nothing marks the start, history never reports `end_of_list`; say so in the README.

## Overlays

`Overlays.swift`:

```swift
public enum OverlayKind: Equatable { case modal, sheet }

public enum Overlays {
    /// Kinds currently open in the Slack window.
    public static func open(in tree: SlackTree) -> [OverlayKind]
    /// Presses the ReactModal__Overlay node, then polls until no modal is open and the primary view is back.
    /// Throws overlay_left_open at the deadline.
    public static func closeModal(in tree: SlackTree, deadline: Date) throws
    /// Runs `opening`, waits for exactly one modal, passes it to `body`, and closes it on every exit path.
    public static func withModal<T>(in tree: SlackTree, deadline: Date,
                                    opening: () throws -> Void,
                                    _ body: (any UINode) throws -> T) throws -> T
}
```

Rules:

- A command never closes an overlay it did not open. If an overlay is open when a command starts, the command fails with `ui_blocked`. This applies to every command except `doctor` and `inspect`.
- A command that opens an overlay closes it before returning, on success and on failure. If it cannot, it throws `overlay_left_open`, which tells the caller Slack was left with a popup on screen.
- `withModal` verifies that the primary view locator matches again after closing.

## Bounded paging

`VirtualListPager.swift` gives every list in v1.0 the same bounded loop.

```swift
public enum StopReason: String, Encodable {
    case boundary        // the caller's stop condition was met
    case endOfList = "end_of_list"
    case limit           // maxItems or maxPages reached
    case stalled         // three rounds in a row produced nothing new
    case deadline
}

public struct PageBounds { public var maxItems: Int; public var maxPages: Int; public var deadline: Date }

public struct Paged<Item> {
    public let items: [Item]
    public let pages: Int
    public let stopReason: StopReason
    public var complete: Bool { stopReason == .boundary || stopReason == .endOfList }
}

public enum PageDirection { case towardStart, towardEnd }

public enum VirtualListPager {
    public static func collect<Key: Hashable, Item>(
        direction: PageDirection,
        bounds: PageBounds,
        rendered: () throws -> [(key: Key, node: any UINode, item: Item)],   // current rows, in list order
        reachedBoundary: (Item) -> Bool,
        atEnd: () throws -> Bool
    ) throws -> Paged<Item>
}
```

One round: call `rendered`, add items with unseen keys, check `reachedBoundary`, `maxItems`, `atEnd`, `maxPages` and the deadline in that order, then perform `.scrollToVisible` on the first rendered node (`towardStart`) or the last (`towardEnd`) and poll every 100 ms for up to 1.5 s until a new key appears. Three consecutive rounds with no new key stop with `stalled`. Items are returned in list order regardless of direction.

Add `case scrollToVisible = "AXScrollToVisible"` and `case showMenu = "AXShowMenu"` to `UIAction`.

No silent partial results, for every list-returning command in v1.0:

- The result always carries `complete`, `stopReason` and `pages`.
- `limit` and `boundary` are what the caller asked for: exit status 0.
- `stalled` and `deadline` mean the tool fell short: the command fails with `partial_result` (exit status 19) and prints nothing on stdout, unless `--allow-partial` is passed, in which case it prints the items with `complete: false` and exits 0.

## History

```
slack-remote read ... --history [--since <TS>] [--max-messages <N>] [--max-pages <P>] [--allow-partial]
```

`--history` requires destination flags or `--dest`. Defaults: 200 messages, 50 pages. `--max-messages` above 2000 is an argument error. `--since` is a message timestamp; paging stops when a message at or before it has been collected, and older messages are dropped from the result.

`History.swift` pages `towardStart` over the message list with the message timestamp as key, running `MessageReader` on each round, because the virtual list drops items as it scrolls. Afterwards it performs `.scrollToVisible` on the item with id `message-list_bottomSpacer` and reports whether the newest collected message is rendered again within 2 s.

```json
"result": {
  "team": "T0AAAAAAA", "conversation": "C0BBBBBBB", "route": "deep_link_channel",
  "scope": "history", "complete": true, "stopReason": "boundary", "pages": 4,
  "oldestTs": "1700000000.000100", "newestTs": "1700000900.000300",
  "scrollRestored": true, "readAt": "2026-11-24T21:00:00Z",
  "skippedItems": 0, "messages": [ ]
}
```

Plain `read` keeps `scope: "rendered"` and gains `"complete": false, "stopReason": "limit", "pages": 0` so both shapes carry the same fields. The result is a snapshot taken at `readAt`. A message that arrives during paging is included when Slack renders it; there is no follow mode.

## Accounts and named destinations

`Config.swift` reads `~/.config/slack-remote/config.json`. The tool creates it with mode `0600` and refuses to read one that is group- or world-readable (`config_invalid`).

```json
{
  "accounts": [ { "team": "T0AAAAAAA", "user": "U0EEEEEEE", "selfDM": "D0CCCCCCC" } ],
  "destinations": { "notes": { "team": "T0AAAAAAA", "conversation": "G0FFFFFFF" } },
  "restrictWritesToDestinations": false
}
```

Commands:

- `slack-remote whoami [--save]` reports `{ "team", "user", "selfDM" }` for the workspace Slack is showing. `team` comes from the web area URL. `selfDM` is the id of the sidebar row containing `p-channel_sidebar__channel--im-you`, or null when that row is not rendered. `user` is read from the search modal: inside `Overlays.withModal`, press `p-top_nav__search`, find exactly one `AXCheckBox` whose id starts with `quick-filter-from-`, and take the rest of the id. To close: if a button with class `c-search__input_box__clear` exists, press it first; then `closeModal`. `--save` writes or replaces the account entry for that team.
- `slack-remote dest add <NAME> --team <TEAM_ID> --channel <CONVERSATION_ID>` and `slack-remote dest list` edit and print `destinations`. Names match `^[a-z0-9_-]{1,32}$`.
- Every command that takes `--team` and `--channel` also accepts `--dest <NAME>` in their place. Giving both is an argument error.

`Account.verify(team:in:)` runs in every command that has a destination, after navigation:

1. No config file: reads proceed; writes proceed with the warning `no_account_configured`.
2. Config file exists but has no account for the team: reads add the warning `account_unverified`; writes fail with `account_unverified`.
3. The `im-you` row is rendered: its id must equal `selfDM`. A different id fails with `account_mismatch`.
4. The row is not rendered: reads add `account_unverified`; writes run the search-modal check from `whoami` and compare `user`.

With `restrictWritesToDestinations` true, a write whose team and conversation do not equal some entry in `destinations` fails with `write_not_allowed` before Slack is touched.

## Dry run

Add `--dry-run` to `open`, `draft set`, `draft clear` and `send`; later issues add it to their writing commands. A dry run validates arguments and text, runs preflight, lock and tree session, resolves `--dest`, checks write restriction and the account by sidebar only, and reads the current location. It does not navigate, focus, open anything, write or press.

```json
"result": {
  "dryRun": true,
  "team": "T0AAAAAAA", "conversation": "C0BBBBBBB",
  "atDestination": false,
  "account": "verified",
  "composer": "unknown",
  "plan": ["navigate via deep_link_channel", "verify destination", "write text (31 characters)", "final gate", "press send once", "confirm message"]
}
```

`composer` is `empty`, `text` or `pending` when Slack is already at the destination, and `unknown` otherwise. A blocker that is already visible, such as a different draft in the composer, fails the dry run with the same error the real command would give.

## Command stubs and per-command docs

Register these commands now so later issues add no line to `Main.swift`: `reply`, `react`, `channels`, `members`, `people`, `search`, `upload`. Each is a file under `Sources/slack-remote/Commands/` whose `run` throws `not_implemented`. Each later issue replaces its own files.

Create `docs/commands/` with one Markdown file per existing command (`doctor`, `current`, `open`, `read`, `draft`, `send`, `whoami`, `dest`, `inspect`), moved out of `README.md`: synopsis, options, result shape, errors. Add a section to `README.md` on what each command changes:

- Nothing: `doctor`, `current`, `inspect`, `dest`, `read` without a destination, any `--dry-run`.
- The view only (conversation shown, scroll position, a popup opened and closed): `open`, `read` with a destination or `--history`, `whoami`. Slack treats a conversation the tool opens as viewed, exactly as when a person opens it, so unread markers can clear.
- Content: `draft`, `send`.

## Errors

Add to `RemoteError` and the exit table:

| Exit | New codes |
|---|---|
| 1 | `not_implemented` |
| 12 | `overlay_left_open` |
| 13 | `message_not_rendered`, `unsupported_destination` |
| 15 | `write_not_allowed`, `file_rejected` |
| 17 | `reaction_unconfirmed`, `upload_unconfirmed` |
| 19 | `partial_result` |
| 20 | `account_mismatch`, `account_unverified`, `config_invalid` |

## Files

Create: `Sources/SlackRemoteCore/{Overlays,VirtualListPager,History,Config,Account,DryRun,Inspector}.swift`; `Sources/slack-remote/Commands/{Whoami,Dest,Inspect,Reply,React,Channels,Members,People,Search,Upload}.swift`; `Tests/SlackRemoteCoreTests/{Overlays,VirtualListPager,History,Config,Account,Inspector}Tests.swift`; `Tests/SlackRemoteCoreTests/Support/PagingFixtures.swift`; `docs/commands/*.md` for the nine commands above; `docs/validation/v1-foundation.md`.

Modify: `Main.swift`, `CommandSupport.swift`, `Commands/{Open,Read,Draft,Send}.swift`, `UINode.swift`, `AXNode.swift`, `RemoteError.swift`, `Locators.swift` (new section "Overlays and account"), `Tests/SlackRemoteCoreTests/Support/FakeNode.swift`, `README.md`, and for the amendments only: `Navigator.swift`, `SlackApp.swift`, `SlackWindow.swift`, `Sender.swift`, `Composer.swift` with their tests.

## Tests

- `VirtualListPagerTests`, with a fake list that reveals older rows on `scrollToVisible`: stops on `boundary`, `limit` by items, `limit` by pages, `end_of_list`, `stalled` after three empty rounds, `deadline`; returns list order; never duplicates a key.
- `HistoryTests`: messages dropped by the list between rounds are still returned; `--since` trims older messages; `stalled` without `--allow-partial` throws `partial_result`.
- `OverlaysTests`: an overlay open at start gives `ui_blocked`; `withModal` closes after a throwing body; a modal that will not close gives `overlay_left_open`.
- `ConfigTests` and `AccountTests`: each of the four `Account.verify` cases; `restrictWritesToDestinations`; a world-readable file is refused.
- `InspectorTests`: titles and values never appear in output; ids are masked.
- One dry-run test per command showing that no `set`, `perform` or link open is recorded on the fake.

## Live validation

Record results in `docs/validation/v1-foundation.md` using destination names only, never ids, names of people or message text.

The two designated destinations are `notes` (the channel `#juannotes`) and `self` (the signed-in user's own DM). Set them up once with `dest add`, using ids read from `current` after opening each by hand, then run `whoami --save`.

1. `whoami`: plausible ids, search modal closed afterwards, conversation unchanged.
2. `inspect` in each scope: output contains no text from the workspace.
3. The start-of-conversation observation from step 1.
4. `read --dest self --history --max-messages 50`: `complete` and `stopReason` are consistent with the conversation's length, messages are in order without duplicates, and the view ends at the newest message.
5. `read --dest notes --history --max-pages 1`: `stopReason` is `limit`, exit status 0.
6. `send --dest notes --text "slack-remote dry run" --dry-run`: Slack does not change, and the plan is printed.
7. With `restrictWritesToDestinations` true, `send --dry-run` to the conversation Slack happened to be showing before the test, by `--team` and `--channel`: `write_not_allowed`.
8. Temporarily edit `selfDM` in the config to another valid-looking id and run `open --dest notes`: `account_mismatch`. Restore the config.

This issue adds no step that writes to Slack. Live validation across v1.0 issues runs one issue at a time; do not run live steps while another worker is running theirs.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- Every list result carries `complete`, `stopReason` and `pages`, and a shortfall exits with status 19 unless `--allow-partial` is given.
- No command returns with a popup it opened still on screen without reporting `overlay_left_open`.
- No command closes a popup it did not open.
- `--dry-run` performs no navigation, write, press or link open.
- With a config file present, a write to a team without a verified account does not happen.
- `inspect` output contains no title, value or URL from Slack.
- The four amendments are present in the code with tests.
- The seven stub commands exist and fail with `not_implemented`.
