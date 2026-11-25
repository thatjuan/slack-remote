<!-- title: Native Slack search: messages, files and other result types, with filters and navigation to a result -->

> Plan labels used in this text. Issues 1 to 3 are the v0.1 issues: foundation with `doctor`, `current` and `open`; `read`; `draft` and `send`. Issue 4 is "Thread read and reply, reactions, and emoji in messages". Issue 5 is "v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run". Issue 6 is "List channels, conversation members and the people directory". Issue 7 is "Native Slack search: messages, files and other result types, with filters and navigation to a result". Issue 8 is "Upload a file to a verified channel, DM or thread". Issue 9 is "Installable v1.0 release and the full validation matrix on main-mac". GitHub numbers may differ from these labels.

Add `slack-remote search`, which runs a query through the Slack client's own search and returns what the client shows: messages, files, and each other result type the client exposes. Results can be filtered to a conversation or sender, paged within bounds, and one message result can be opened in its conversation.

Depends on issues 1, 2, 3 and 5. Use `UINode`, `Locators`, `SlackWindow`, `Navigator`, `MessageReader`, `Overlays`, `VirtualListPager`, `Account`, `RemoteError` and the output envelope as they are. The hard boundaries from issue 1 apply: Accessibility reads, attribute writes and semantic actions; no Slack API or endpoints; no synthetic keyboard or mouse events; no coordinate-based clicks.

## What was observed on the real client

Slack 4.53.292, structure only. No query was typed during planning.

- The `AXButton` with class `p-top_nav__search` opens the search modal: a `ReactModal__Content` node containing `c-search_modal__wrapper`.
- The query field is an `AXComboBox` with class `ql-editor`, and `ql-blank` when empty. `AXValue` and `AXSelectedText` report as settable. It has focus when the modal opens.
- Quick filters are `AXCheckBox` nodes with `AXPress` and these ids: `quick-filter-in-<ID>` for the conversation the modal was opened from, `quick-filter-from-<USER_ID>` for the signed-in user, `quick-filter-with-<USER_ID>`, `quick-filter-has-link`, `quick-filter-is-thread`. An `AXPopUpButton` with id `quick-filter-add` opens more filters.
- A filter that is active shows as a group with class `c-member_slug--search-filter` inside the query field.
- Suggestions are in an `AXList` with id `c-search_autocomplete__suggestion_list`. Entity suggestions have ids `c-search_autocomplete__suggestion_<n>` and support `AXPress`. A row with class `c-search_autocomplete__suggestion_item--query` stands for "run this query"; with an empty field it offered no press action.
- With content in the field a `Clear` button exists (`c-search__input_box__clear`). With an empty field an overlay node exists and `AXPress` on it closes the modal.
- The modal survives a deep-link navigation; it must be closed explicitly.
- While the modal is open, the primary view is absent from the tree.

Not observed: writing a query into the field, any way to submit it, and everything about the results view.

## Step 1: probe, in this order

Use `slack-remote inspect`. Run queries only with the filter for the `notes` or `self` destination active, and only with synthetic terms such as `slack-remote test`, so the results come from the designated conversations. A query is stored in Slack's recent searches; that is the one lasting effect of this issue's validation, and the validation file must say so. Record every answer in `docs/validation/search.md`.

1. Query entry. Open the modal from the `notes` destination. Try, in order: set `AXFocused` then `AXSelectedText` on the query field; set `AXValue`. Record which makes the text appear (read back `AXValue`) and whether suggestions update.
2. Submit. With a query present, look for a semantic submit, in this order:
   a. the `c-search_autocomplete__suggestion_item--query` row now supports `AXPress`;
   b. any action on the query field other than `AXPress`, `AXShowMenu` and `AXScrollToVisible` (list them all);
   c. a button inside the modal that runs the search.
3. If none of a to c submits the query, stop here and report on this issue with the recorded structure. The remaining candidate is one Return key delivered to Slack with the Accessibility function `AXUIElementPostKeyboardEvent` while the query field is verified to hold focus. That is a keyboard event and is outside the project's hard boundaries, so it needs Juan's explicit approval before any code uses it. Do not use `CGEvent`, AppleScript or any other key path. Without a submit route this issue is blocked; it is not to be closed as done.
4. Results view. After a submit: the web area URL shape; the result-type tabs, with their ids and which is selected; the list container and row locator for each type; where a message result carries its conversation id and timestamp, and a file result its file id; the sort control; the filter controls; whether `AXScrollToVisible` on the last row loads more; how "no results" appears.
5. Leaving. How the results view is closed so the previous conversation shows again. A deep link to the starting conversation is the expected route; confirm it.

Use what step 4 finds to fill `Locators+Search.swift`. Ids and classes only; never a localised label.

## Command

```
slack-remote search --query <TEXT>
    [--type messages|files|channels|people|<other tab id>]      default: messages
    [--in <NAME> | --in-team <TEAM_ID> --in-channel <CONVERSATION_ID>]
    [--from-me]
    [--has-link] [--threads-only]
    [--max-results <N>] [--max-pages <P>] [--allow-partial]
    [--open <INDEX>]
    [--team <TEAM_ID>]
```

- `--query` is passed to Slack as typed. Slack's own modifiers, such as `in:`, `from:`, `before:` and `has:`, work because Slack parses them; the tool does not interpret them. Refuse an empty query and control characters.
- `--in` navigates to that conversation first, opens the modal from there, and presses the `quick-filter-in-<ID>` toggle whose id ends with the conversation id (for a DM, the id it ends with is recorded in step 1). The filter is confirmed by a `c-member_slug--search-filter` node appearing in the query field. If the toggle's id does not match, fail with `ui_drift`.
- `--from-me`, `--has-link` and `--threads-only` press `quick-filter-from-…`, `quick-filter-has-link` and `quick-filter-is-thread`.
- `--type` selects a result tab by the id found in step 4. Types the client does not show fail with `unsupported_destination` and list the available tab ids in the error details.
- Defaults: 50 results, 20 pages; `--max-results` above 1000 is an argument error.

Order of work: preflight, lock, tree session, overlay check, `Account.verify`, navigation if `--in` or `--team` was given, open the modal, set filters, write the query with the method from step 1, read it back and require equality after `MessageText.normalize`, submit, wait for the results view, select the tab, page, read, leave the results view by deep link to the conversation that was showing at the start, and verify arrival.

```json
"result": {
  "team": "T0AAAAAAA", "query": "slack-remote test", "type": "messages",
  "filters": { "in": "G0FFFFFFF", "fromMe": false, "hasLink": false, "threadsOnly": false },
  "availableTypes": ["messages", "files", "channels", "people"],
  "sort": "most_relevant",
  "complete": true, "stopReason": "end_of_list", "pages": 1,
  "returnedTo": "D0CCCCCCC",
  "results": [
    { "index": 0, "kind": "message", "conversation": "G0FFFFFFF", "ts": "1700000000.000100",
      "sender": "Ada", "text": "slack-remote test 1", "idSource": "dom_id" }
  ]
}
```

Per kind, a result carries what the client exposes: `message` has `conversation`, `ts`, `sender`, `text`; `file` has `file` (id), `name`, and `conversation` when shown; `channel` has `conversation`, `name`; `person` has `user`, `label`. `idSource` is `dom_id` when the id was read from a non-text attribute, or `none` when the client shows a result without one, in which case the id fields are null. Results with `idSource: "none"` cannot be opened.

Honest scope, stated in `docs/commands/search.md`:

- Results are Slack's, in Slack's order, at the moment of the search. The tool does not rank, deduplicate across types, or guarantee that Slack returned everything that matches.
- `complete: true` means the tool reached the end of what the client lists for that tab, not that the workspace holds no other match.
- Message text in a result is the excerpt the results view renders, which Slack may truncate.

### `--open <INDEX>`

After reading, press the result row with that index, then verify: the web area URL shows the result's team and conversation, and an item with id `message-list_<ts>` is rendered in the primary view (for a thread reply, `verifyThread` from issue 4 is not required; report `"inThread": true` when the pane opened). The command then leaves Slack on that conversation and does not return to the starting one. Only `message` results with `idSource: "dom_id"` can be opened; anything else fails with `unsupported_destination`. If verification fails, report `destination_mismatch`.

## Leaving nothing behind

- The modal and the results view are closed on every exit path. If the modal cannot be closed, `overlay_left_open`; if the starting conversation cannot be verified afterwards, `destination_mismatch` with the results still withheld.
- The query field is cleared with the `Clear` button before closing when a failure happens before submit, so no half-typed query stays in the modal.
- Filters toggled by the command are toggled back if a failure happens before submit. Record in step 1 whether filter state persists across modal opens; if it does, restore it after a successful search as well.

## Files

Replace the stub `Sources/slack-remote/Commands/Search.swift`.

Create: `Sources/SlackRemoteCore/{SearchModal,SearchResults}.swift`, `Sources/SlackRemoteCore/Locators+Search.swift`, `Tests/SlackRemoteCoreTests/{SearchModal,SearchResults}Tests.swift`, `Tests/SlackRemoteCoreTests/Support/SearchFixtures.swift`, `docs/commands/search.md`, `docs/validation/search.md`.

Modify nothing else.

## Tests

Fixtures mirror the structures recorded in step 1.

- `SearchModalTests`: the filter toggle whose id ends with the requested conversation is the one pressed; a toggle for another conversation gives `ui_drift`; a query that reads back differently is not submitted and the field is cleared; the modal is closed when a step throws.
- `SearchResultsTests`: one extraction test per result kind; a result without an id has `idSource: "none"` and null ids; paging stops on `limit` and on `end_of_list`; `stalled` without `--allow-partial` gives `partial_result`; `--open` presses exactly the indexed row and fails with `destination_mismatch` when the URL does not match; opening a result without an id is refused before any press.

## Live validation

Only with the `notes` or `self` filter active and synthetic terms. Seed the `notes` destination by hand with three messages containing `slack-remote test` and one uploaded text file named `slack-remote-test.txt`. Record outcomes in `docs/validation/search.md` without ids, names or message text.

1. The five probe steps, including the decision at step 3.
2. `search --query "slack-remote test" --in notes`: the three seeded messages are returned with ids, `complete` is true, Slack is back on the starting conversation, no popup is open.
3. The same with `--type files`: the seeded file is returned.
4. Each other tab id in `availableTypes`: the command returns without error, with results or an empty list.
5. A query with no matches: empty `results`, `complete: true`, exit status 0.
6. `--max-results 1`: `stopReason` is `limit`.
7. `--open 0` on the message search: Slack shows the `notes` conversation with that message rendered.
8. Start a search and interrupt it with Ctrl-C after the modal opens: the next `doctor` shows no popup, or the interrupted command reported `overlay_left_open`.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- The query submitted equals the query requested; a read-back mismatch submits nothing.
- A filter is applied only through a toggle whose id carries the requested id.
- Every result's ids come from non-text attributes, or are null with `idSource: "none"`.
- Every result set carries `complete`, `stopReason` and `pages`; a shortfall exits with status 19 unless `--allow-partial` is given.
- After a search without `--open`, Slack shows the conversation it showed before, with no popup open.
- The package contains no key-event code unless the step 3 exception was approved in writing on this issue, in which case it is confined to one function that posts Return to Slack's application element after verifying focus on the query field.
- `docs/validation/search.md` records the probe answers, which result types the client exposed, and each live step's outcome.
