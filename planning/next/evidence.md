# Probe evidence for the complete CLI

A second round of probes on Slack 4.53.292, main-mac, macOS 27.2.1. It extends `planning/evidence.md`. The probes recorded roles, subroles, DOM classes, id shapes and action names. Ids were held in memory and never printed; no message text, name or URL was recorded.

## What the probes did

Navigation and opening of panels happened only in the two designated destinations, `#juannotes` and the self-DM, and each run returned Slack to the conversation it started in. Nothing was sent, reacted to, uploaded, typed into a composer or search box, or selected in a picker. Every popup, the thread pane and the file panel that a probe opened was closed again and the close was confirmed by a later read.

One slip: a generic "close" heuristic pressed the search modal's "Hide filters" toggle twice, which left it in its original state. The heuristic was removed.

## Designated destinations can be identified

- Exactly one sidebar row has a name equal to `juannotes`. Its id starts with `G`.
- Exactly one sidebar row contains the class `p-channel_sidebar__channel--im-you`. That is the self-DM, and its id starts with `D`.

## Navigation

| Route | Result |
|---|---|
| `slack://channel?team=…&id=G…`, opened with `activates = false` | Arrived in 0.2 s. URL and selected sidebar row matched. |
| `slack://channel?team=…&id=D…` | Arrived in 0.2 s, same checks. The documented link accepts a DM id. |
| `AXPress` on the sidebar `AXRow` | Returned success. Slack did not navigate within 8 s. |
| `AXPress` on the group with class `p-channel_sidebar__channel` inside the row | Arrived in 0.2 s. |

Slack was already the frontmost application during these runs, so whether a link brings Slack forward is still unobserved.

## History

A message item supports the action `AXScrollToVisible`. Performing it on the oldest rendered item made Slack render older messages: three rounds took the set of seen message ids from 3 to 16, while the virtual list dropped items at the other end. Performing it on the newest item and on `message-list_bottomSpacer` returned success. This gives history paging through a semantic action.

How the start of a conversation appears in the tree was not observed.

## Message actions

- Setting `AXFocused` on a message item, or on a link inside it, returned success and did not reveal the hover toolbar.
- The action `AXShowMenu` on a message item opens Slack's "Message actions" menu: an `AXMenu` with class `c-menu__items` inside a `ReactModal__Content` popover. The message item gains the class `c-virtual_list__item--contextmenu-visible` while the menu is open.
- Its items are `AXMenuItem` nodes with `AXPress` and one distinguishing class each: `p-message_actions_menu__add_reaction`, `p-message_actions_menu__comment` (reply in thread), `p-message_actions_menu__share_message`, `p-message_actions_menu__mark_unread`, `p-message_actions_menu__later`, `p-message_actions_menu__subscribe`, `p-message_actions_menu__copy_link`, `p-message_actions_menu__delete_message`.
- `AXCancel` on the menu returns success and leaves it open. `AXPress` on the `AXGroup` with class `ReactModal__Overlay` closes it.

## Thread pane

Pressing `p-message_actions_menu__comment` opens the thread pane.

- The pane is an `AXGroup` with classes `p-view_contents p-view_contents--secondary` and subrole `AXApplicationDialog`.
- The web area URL does not change when a thread opens.
- Items in the pane's list have ids of the form `<CONVERSATION_ID>-<ROOT_TS>-thread-list-Thread_<TS>`, and the composer row has `<CONVERSATION_ID>-<ROOT_TS>-thread-list-Thread_input`. The conversation and the root message are both in the id.
- The pane has its own `ql-editor` text area, its own send button, and its own Attach button.
- An "also send to channel" checkbox has class `c-input_checkbox` and id `p-thread_footer__broadcast_checkbox--<CONVERSATION_ID>-<ROOT_TS>--Thread`.
- The pane's toolbar has class `p-flexpane_header`. Its close control is the `AXButton` with class `p-flexpane_header__control`; the other control with that class is an `AXPopUpButton`. Pressing the button closes the pane.

Only a thread with no replies was opened. A thread with replies and the reply bar under a message were not observed.

## Emoji picker

Pressing `p-message_actions_menu__add_reaction` opens the picker.

- It is an `AXGroup` with class `p-emoji_picker`, subrole `AXApplicationDialog`, inside `ReactModal__Content`.
- The search field is an `AXTextField` with class `p-emoji_picker__input`; `AXValue` reports as settable.
- Each emoji is an `AXCell` with class `p-emoji_picker__list_item`, action `AXPress`, and id `emoji-picker-<short_name>`, for example `emoji-picker-tada`.
- Category tabs are `AXRadioButton` nodes with ids such as `smileys-&-people-emoji-tab`. The grid is virtualised.
- `AXPress` on the overlay closes the picker.

Not observed: whether setting the search field filters the grid, and how an existing reaction node names its emoji.

## Attach menu and file panel

- The Attach control is the `AXPopUpButton` with class `c-wysiwyg_container__button--shortcuts`. It opens an `AXMenu` of four `AXMenuItem` nodes that share the class `c-menu_item__button` and have ids `menu-<n>-0` to `menu-<n>-3`. The fourth is "Upload from your computer". No class distinguishes the items.
- Pressing the fourth item opens a native `AXSheet` on the Slack window. It contains a sidebar `AXOutline`, an `AXBrowser`, an `AXSearchField` whose value is settable, a location `AXPopUpButton`, and `Cancel` and `Open` buttons. It has no field for typing a path.
- `AXPress` on `Cancel` closed the sheet. The composer was still empty afterwards.

Slack's `Info.plist` declares one document type, `slacktoken`, and no services or share extension. Opening an arbitrary file with Slack is therefore not a documented upload route.

## Channel details and members

Pressing the first `AXButton` with class `p-avatar_stack--details` in the conversation header opens the details modal on its Members tab.

- The modal is `ReactModal__Content` with classes `c-sk-modal p-about_modal`, subrole `AXApplicationDialog`.
- Tabs are `AXRadioButton` nodes with ids `about`, `members`, `agents`, `integrations`, `tabs`, `settings`. The Members tab's label carries the member count.
- Each member is an `AXGroup` with class `p-ia_details_popover__members_list_item_member` whose id is the user id. The list is virtualised and has a filter field.
- The close control is an `AXButton` with class `c-sk-modal__close_button`. `AXPress` on the overlay also closed the modal.

## Search modal

Pressing the `AXButton` with class `p-top_nav__search` opens the search modal.

- It is `ReactModal__Content` with subrole `AXApplicationDialog`, containing `c-search_modal__wrapper`.
- The query field is an `AXComboBox` with class `ql-editor`; `AXValue` and `AXSelectedText` report as settable. It takes focus when the modal opens.
- Quick filters are `AXCheckBox` nodes with ids `quick-filter-in-<CONVERSATION_ID>` (or the other user's id in a DM), `quick-filter-from-<USER_ID>`, `quick-filter-with-<USER_ID>`, `quick-filter-has-link`, `quick-filter-is-thread`, and a pop-up `quick-filter-add`. The `from` filter's id is the signed-in user's id.
- Suggestions are in an `AXList` with id `c-search_autocomplete__suggestion_list`. Entity suggestions have ids `c-search_autocomplete__suggestion_<n>` and support `AXPress`. The row that would run the typed query showed no press action while the field was empty.
- The modal stays open across a deep-link navigation.
- Closing: with content in the field there is a `Clear` button (`c-search__input_box__clear`); once the field is empty an overlay node exists and `AXPress` on it closes the modal.

Not observed: typing a query, submitting it, the results view, its tabs, filters and URL.

## While a modal is open, the rest of the tree is gone

With the search modal, the details modal or the picker open, `p-view_contents--primary` is absent from the tree. A command that looks for the primary view at that moment finds nothing.

## Another process can remove the tree mid-command

Implementation workers were validating the MVP against the same Slack during these probes. Three probe runs found a web area with no URL, or lost the tree partway through, and the conversation changed between runs. The cause is two tools setting and clearing `AXManualAccessibility` independently: one tool's restore removes the tree under the other. The MVP lock serialises `slack-remote` invocations and cannot cover other tools.

## Still unobserved

| Area | Missing observation | Settled in |
|---|---|---|
| Search | Query entry, a semantic way to submit, results structure, tabs, filters, URL | Issue 7 |
| Channel browser and people directory | Structure of the views behind Go › Channel Browser and Go › People & User Groups | Issue 6 |
| Sidebar paging | Whether `AXScrollToVisible` pages the sidebar as it pages messages | Issue 6 |
| Upload | Selecting a file in the sheet by its URL, the pending-file element in the composer | Issue 8 |
| Reactions | Emoji identity on an existing reaction, picker filtering | Issue 4 |
| Threads | A thread with replies | Issue 4 |
| Emoji in text | How the composer and a rendered message expose `:name:` emoji | Issue 4 |
| History | The start-of-conversation marker | Issue 5 |
| Focus | Whether a link activates Slack when another application is frontmost | Issue 1 validation |
