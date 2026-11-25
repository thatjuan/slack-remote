# Probe evidence

What was observed in the stock Slack desktop client through macOS Accessibility, what was not, and what each fact means for the design. Every probe recorded roles, DOM classes, DOM ids with identifiers masked, action names and settability. No message text, sender, channel name, workspace name, account identity or URL was recorded; the notes below describe shapes only.

## Probe conditions

| | |
|---|---|
| Host | main-mac, macOS 27.2.1, user logged in at the console, screen unlocked |
| Slack | 4.53.292, bundle id `com.tinyspeck.slackmacgap`, one window, frontmost |
| Probe process | a Swift binary started from a process inside the GUI login session; `AXIsProcessTrustedWithOptions` (no prompt) returned true |
| Earlier probe | jmbp, Slack 4.52.178, read-only: a real AX tree with windows, rows, buttons, links and two writable text controls |
| Writes performed | one: `AXManualAccessibility` on Slack's application element, set to true for 2.9 s and set back to false |
| Not performed | no link opened, no focus or conversation change, no text typed, no button pressed, no message sent, no reaction, no draft touched, no permission granted |

## Observed facts

### The accessibility tree is off by default

With `AXManualAccessibility` at its default, Slack exposes 12 nodes: the window, three title-bar buttons and a chain of empty Chromium `View` groups. The native menu bar is fully readable in this state.

Setting `AXManualAccessibility` to true on the application element returned success. The web content tree appeared about 2.1 s later (polled every 150 ms). Setting it back to false returned success, and a later read-only walk found 13 nodes again, so the switch-off takes effect.

Reading `AXManualAccessibility` returned false at every point, including immediately after setting it to true. The attribute value cannot be used to detect or confirm the mode. The presence of an `AXWebArea` under the window is the reliable signal.

`AXEnhancedUserInterface` was never written.

### Cost of a full walk

With the tree populated, the whole window is 438 nodes at a maximum depth of 30. A walk that fetches role, subrole, DOM classes, DOM id and children with one `AXUIElementCopyMultipleAttributeValues` call per node, plus one action-name call per node, took 0.07 s. Full walks are cheap enough that no search optimisation is needed.

### The web area URL identifies the destination

The window holds exactly one `AXWebArea`. Its `AXURL` has the shape

```
https://app.slack.com/client/<TEAM_ID>/<CONVERSATION_ID>
```

where the team segment is `T` plus 8 characters and the conversation segment was `C` plus 8 characters for the open channel. This gives an exact, locale-independent destination check that does not depend on any name.

The window `AXTitle` has the shape `<name> (Channel) - <workspace> - Slack`. The window's own `AXDocument` attribute is an empty string.

### Sidebar

The sidebar is an `AXOutline` with class `c-virtual_list__scroll_container`. Each conversation is an `AXRow` (subrole `AXOutlineRow`) with class `p-channel_sidebar__static_list__item` whose `AXDOMIdentifier` is the conversation id: `C…` for channels and group DMs, `D…` for DMs, and one `G…` row. Rows support `AXPress` and have a settable `AXFocused`.

- The open conversation's row carries the class `p-channel_sidebar__static_list__item--selected`.
- The row's inner group carries `p-channel_sidebar__channel--draft` when that conversation holds a draft, `p-channel_sidebar__channel--mpim` for a group DM, and `p-channel_sidebar__channel--im-you` for the user's own self-DM.
- Fixed rows have ids `Punreads`, `Vall_threads`, `Pdrafts`, `Pbookmarks`; section headers have ids `sectionHeading-<id>`.
- The list is virtualised, so a conversation that is scrolled out of the sidebar has no row.

### Primary view and message list

The open conversation lives in an `AXGroup` with classes `p-view_contents p-view_contents--primary`. Inside it:

- The header is an `AXToolbar` with class `p-view_header`.
- The message list is an `AXList` (subrole `AXContentList`) inside `p-message_pane`.
- Each list item is an `AXGroup` with class `c-virtual_list__item`. A message item has `AXDOMIdentifier` of the form `message-list_<10 digits>.<6 digits>`, which is the Slack message timestamp. Day dividers and spacers have other ids (`message-list_<13 digits>…`, `message-list_bottomSpacer`).
- Inside a message item is an `AXGroup` with subrole `AXDocument`, role description `message`, class `c-message_kit__hover`.
- The sender is an `AXButton` with class `c-message__sender_button`. Consecutive messages from the same sender omit it.
- The time is an `AXLink` with class `c-timestamp`.
- Body text sits under `AXGroup` nodes with class `p-rich_text_section`, as `AXStaticText` and `AXLink` children.
- Attachments appear under classes beginning `c-message_attachment`.
- A message that already has reactions carries an `AXGroup` with class `c-reaction_bar`. Each existing reaction is an `AXCheckBox` (subrole `AXToggleButton`) with class `c-reaction`, plus `c-reaction--reacted` when the user has reacted; it supports `AXPress`. The bar ends with an `AXButton` of class `c-reaction_add`.

The hover toolbar (reply in thread, add reaction, more actions) is absent from the tree when the message is neither hovered nor focused. No thread pane was open, so the secondary view was not observed.

### Composer

Inside the primary view, an `AXGroup` with class `p-message_input_unstyled` wraps the composer.

- The editor is one `AXTextArea` with classes `ql-editor ql-blank`. `ql-blank` marks an empty editor; `AXNumberOfCharacters` was 1 in that state.
- `AXValue`, `AXFocused`, `AXSelectedTextRange` and `AXSelectedText` all report as settable on it. Its parameterised attributes include `AXReplaceRangeWithText` and `AXStringForRange`.
- The send control is an `AXButton` with class `c-wysiwyg_container__button--send`. With an empty editor it also carries `c-button--disabled` and `AXEnabled` is false. It supports `AXPress`.
- The schedule control is a separate `AXPopUpButton` with class `c-wysiwyg_container__button--send_options`.

### Locale independence

Every element the design needs can be found by role, subrole, DOM class and DOM id. Titles and descriptions are localised and are not needed as locators.

### Native menu bar

Readable without the accessibility switch: Slack, File, Edit, View, Go, History, Window, Help. Items include File › New Message, Edit › Paste, Go › Switch to Channel, Go › Threads and Go › Drafts & sent, each a native menu item.

### Documented deep links

Slack's deep-linking reference (docs.slack.dev/interactivity/deep-linking, read 2026-11-24) documents `slack://open`, `slack://open?team={TEAM_ID}`, `slack://channel?team={TEAM_ID}&id={CHANNEL_ID}`, `slack://user?team={TEAM_ID}&id={USER_ID}`, `slack://file`, `slack://share-file` and `slack://app`. It documents no parameter for a specific message or thread, and does not say that `slack://channel` accepts DM ids. Slack registers the `slack` URL scheme in its `Info.plist`.

### Session and focus

`CGSessionCopyCurrentDictionary` returned `kCGSSessionOnConsoleKey = 1` and `kCGSessionLoginDoneKey = 1`; the `CGSSessionScreenIsLocked` key was absent with the screen unlocked. The frontmost application was the same before and after the probe, and the focused element inside Slack did not change.

## Not observed

Each item below is a design assumption until the implementing issue observes it on a disposable destination.

| Unobserved operation | Where it is settled |
|---|---|
| Opening any `slack://` link, and whether Slack activates itself when one is opened with `activates = false` | Issue 1 |
| Whether `slack://user` lands on the expected `D…` id | Issue 1 |
| `AXPress` on a sidebar row | Issue 1 |
| Tree availability when Slack is hidden, minimised, on another Space, or when the screen is locked | Issue 1 |
| Behaviour from a process outside the GUI session, such as an ssh shell | Issue 1 |
| Reading `AXValue` of message text nodes (only their presence was recorded) | Issue 2 |
| Which of `AXSelectedText`, `AXValue` or `AXReplaceRangeWithText` puts text into the Quill editor, and what `AXValue` reads back | Issue 3 |
| `AXPress` on the send button, and the tree after a send | Issue 3 |
| Whether Slack persists a draft written through Accessibility | Issue 3 |
| Thread pane structure, thread URL shape, hover toolbar and emoji picker | Issue 4 |
| Enterprise Grid (`E…` in the URL), signed-out state, multiple Slack windows | Flagged as limits in Issue 1 |
| Slack 4.52.178 on jmbp beyond the earlier read-only summary | Validation on jmbp |
