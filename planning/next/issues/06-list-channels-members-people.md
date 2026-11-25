<!-- title: List channels, conversation members and the people directory -->

> Plan labels used in this text. Issues 1 to 3 are the v0.1 issues: foundation with `doctor`, `current` and `open`; `read`; `draft` and `send`. Issue 4 is "Thread read and reply, reactions, and emoji in messages". Issue 5 is "v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run". Issue 6 is "List channels, conversation members and the people directory". Issue 7 is "Native Slack search: messages, files and other result types, with filters and navigation to a result". Issue 8 is "Upload a file to a verified channel, DM or thread". Issue 9 is "Installable v1.0 release and the full validation matrix on main-mac". GitHub numbers may differ from these labels.

Add three read-only listing commands: `channels`, `members` and `people`. Each returns ids the other commands accept, and each reports honestly whether the list is complete.

Depends on issues 1, 2, 3 and 5. Use `UINode`, `Locators`, `SlackWindow`, `Navigator`, `Overlays`, `VirtualListPager`, `Account`, `RemoteError` and the output envelope as they are. The hard boundaries from issue 1 apply: Accessibility reads and semantic actions, documented links, no Slack API, no synthetic input, no coordinate-based clicks. These commands never write to Slack.

## What was observed on the real client

Slack 4.53.292, structure only.

Sidebar:

- Conversations are `AXRow` nodes with class `p-channel_sidebar__static_list__item` whose id is the conversation id, inside an `AXOutline` with class `c-virtual_list__scroll_container`.
- The row's inner group has class `p-channel_sidebar__channel`, plus `p-channel_sidebar__channel--mpim` for a group DM and `p-channel_sidebar__channel--im-you` for the self-DM. The name is in `AXStaticText` children.
- The list is virtualised. 32 rows were rendered in the probe.

Members of a conversation:

- Pressing the first `AXButton` with class `p-avatar_stack--details` in the header toolbar (`p-view_header`) opens the details modal on its Members tab.
- The modal is a `ReactModal__Content` node with class `p-about_modal`. Its tabs are `AXRadioButton` nodes with ids `about`, `members`, `agents`, `integrations`, `tabs`, `settings`.
- Each member is an `AXGroup` with class `p-ia_details_popover__members_list_item_member` whose id is the user id. It contains one `AXButton` whose title is the member's display text. The list is virtualised.
- Two other items share the list: `anchor_hack_item` and `add_member`.
- The close control is the `AXButton` with class `c-sk-modal__close_button`. `AXPress` on the overlay also closes the modal.

Entry points to the workspace-wide views are native menu items, readable without the web tree: Go › Channel Browser and Go › People & User Groups.

Not observed: the views those two menu items open, whether `AXScrollToVisible` pages the sidebar and the member list as it pages messages, and whether the Members tab label can be parsed for a count in every locale.

## Step 1: structural probe

Use `slack-remote inspect` and record the findings in `docs/validation/listing.md`. These steps change only the view; run them when no other worker is doing live validation, and return Slack to the `self` destination afterwards.

1. Sidebar paging: perform `.scrollToVisible` on the last rendered sidebar row and record whether new rows render.
2. Member list paging: the same inside the details modal of the `notes` destination.
3. Channel browser: press Go › Channel Browser through the native menu bar. Record the web area URL shape, the list container, the row locator, where a row carries its conversation id, and the filter or sort controls.
4. People directory: press Go › People & User Groups. Record the same for people rows, and where a row carries its user id.

Native menu items are found by walking the application's `AXMenuBar`. Titles are localised, so identify the two items by their key equivalents, read from `AXMenuItemCmdChar` and `AXMenuItemCmdModifiers`. Observed values: Channel Browser is `L` with modifiers `1` (Command and Shift), and People & User Groups is `E` with modifiers `1`. Add `NativeMenu.swift` with `func press(cmdChar: String, modifiers: Int) throws`, which searches every top-level menu, requires exactly one enabled item with that pair, performs `AXPress` on it, and throws `ui_drift` otherwise. This presses the menu item; it sends no key event.

For 3 and 4, a row is usable only if it exposes the id (conversation id or user id) in a DOM id or another non-text attribute. If a view exposes names only, that source is not built; the command's `--source` option rejects it with `unsupported_destination`, and the validation file and README say why.

## Commands

All three accept `--max-items <N>` (default 500, maximum 5000), `--max-pages <P>` (default 100) and `--allow-partial`, and return `complete`, `stopReason` and `pages` with the meaning defined in issue 5: a caller's limit is success; `stalled` or `deadline` fails with `partial_result` unless `--allow-partial` is given.

### `slack-remote channels [--source sidebar|browser] [--team <TEAM_ID>]`

`sidebar` (the default) lists the conversations in the user's sidebar. `browser` lists the channels in the channel browser. Without `--team` the command uses the workspace Slack is showing and does not navigate; with `--team` it first opens `slack://open?team=<TEAM_ID>` and verifies the team in the URL.

```json
"result": {
  "team": "T0AAAAAAA", "source": "sidebar",
  "complete": true, "stopReason": "end_of_list", "pages": 3,
  "channels": [
    { "conversation": "C0BBBBBBB", "name": "general", "kind": "channel", "selected": false, "hasDraft": false },
    { "conversation": "D0CCCCCCC", "name": "Ada", "kind": "self_dm", "selected": true, "hasDraft": false }
  ]
}
```

`kind` is `channel`, `group_dm`, `dm` or `self_dm`, taken from the id prefix and the classes above. `name` is the row's static text joined with single spaces. `hasDraft` reflects the class `p-channel_sidebar__channel--draft`. Rows without a conversation id (section headers, fixed pages) are skipped.

The sidebar is paged `towardEnd` from the top and then returned to its original position by performing `.scrollToVisible` on the row that was selected when the command started. `end_of_list` for the sidebar is the row with id `addMoreChannels` or the last section's final row being rendered; decide which from step 1 and document it.

### `slack-remote members --dest <NAME> | --team … --channel …`

Navigates to the conversation, verifies it, and lists its members from the details modal.

1. For a `D…` id, fail with `unsupported_destination`: a DM has no member list.
2. Inside `Overlays.withModal`, press the first `AXButton` with class `p-avatar_stack--details` inside the primary view's `p-view_header` toolbar.
3. Require the modal to have class `p-about_modal` and the tab with id `members` to be selected; if another tab is selected, press the `members` tab once.
4. Page the list `towardEnd`, keyed by item id, keeping items whose id matches the user id pattern.
5. Close with the `c-sk-modal__close_button` button; `withModal` verifies the modal is gone.

```json
"result": {
  "team": "T0AAAAAAA", "conversation": "C0BBBBBBB",
  "complete": true, "stopReason": "end_of_list", "pages": 1,
  "expectedCount": 9,
  "members": [ { "user": "U0EEEEEEE", "label": "Ada Lovelace" } ]
}
```

`expectedCount` is the first integer in the Members tab's title, or null when there is none. When it is present, `complete` is true only if the number of members collected equals it; a mismatch is `stopReason: "stalled"`. When it is absent, completeness follows the pager.

### `slack-remote people [--team <TEAM_ID>]`

Lists the workspace directory from the view behind Go › People & User Groups, in the same result shape as `members` without `conversation`. Afterwards it navigates back to the conversation that was showing. Built only if step 1 finds user ids on the rows.

## Files

Replace the stubs `Sources/slack-remote/Commands/{Channels,Members,People}.swift`.

Create: `Sources/SlackRemoteCore/{SidebarList,MemberList,Directory,NativeMenu}.swift`, `Sources/SlackRemoteCore/Locators+Directory.swift`, `Tests/SlackRemoteCoreTests/{SidebarList,MemberList,Directory}Tests.swift`, `Tests/SlackRemoteCoreTests/Support/DirectoryFixtures.swift`, `docs/commands/{channels,members,people}.md`, `docs/validation/listing.md`.

Modify nothing else. If `UINode` needs an integer accessor for the menu key attributes, add it in `NativeMenu.swift` as an extension on `AXNode` only.

## Tests

- `SidebarListTests`: kinds from id prefix and classes; rows without a conversation id are skipped; paging collects rows the list dropped; the limit stops with `limit`.
- `MemberListTests`: only user-id items are returned; a count mismatch reports `complete: false`; a DM is refused before any press; the modal is closed when paging throws.
- `DirectoryTests`: rows without an id make the source unsupported.

## Live validation

Record in `docs/validation/listing.md`: counts, flags and outcomes only. Do not write channel names, people's names or ids into the file or the pull request.

1. The four probe steps.
2. `channels`: the count matches the sidebar by eye after scrolling it by hand; `notes` and `self` appear with kinds `channel` and `self_dm`; the sidebar ends where it started.
3. `channels --max-items 5`: `stopReason` is `limit`, exit status 0.
4. `members --dest notes`: the count equals `expectedCount`, the modal is closed afterwards, the conversation is unchanged.
5. `members --dest self`: `unsupported_destination`.
6. `channels --source browser` and `people`, if built: counts are plausible, `complete` is consistent, and Slack is back on the starting conversation.
7. After every command: no popup left open.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- Every row returned carries an id read from a non-text attribute.
- Every result carries `complete`, `stopReason` and `pages`, and a shortfall exits with status 19 unless `--allow-partial` is given.
- The commands set no Accessibility attribute. They use `AXPress`, `AXScrollToVisible` and link opens only.
- The view is returned to where it started, and no popup is left open, on success and on failure.
- Each source that could not be built is listed in the README with the observation that ruled it out.
