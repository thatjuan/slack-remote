# Search validation

The live checks used stock Slack 4.53.292 on main-mac with the conversation filter verified against the designated notes alias. The only positive fixture was a synthetic message already sent during foundation validation. The checks used the project lock, wrote no messages or uploads, and stored the submitted terms in Slack’s recent searches.

| Probe | Observation |
| --- | --- |
| Query entry | `AXFocused` and `AXSelectedText` returned success. The field retained its previous value, even when the caret range was set explicitly. `AXValue` wrote the query and updated suggestions. Using it over a filter removed the rich filter chip. The exact toggle could be reapplied after the plain query write, producing the verified query followed by the same filter text. The toggle’s active class and the filter chip confirmed the scope. |
| Submission | A populated query exposed `AXPress` on the query suggestion. When two candidates matched the query class, the pseudo-selected row ran the query. The field exposed `AXPress`, `AXShowMenu`, and `AXScrollToVisible`. The modal buttons were Clear, quick-filter visibility, and feedback controls. The semantic suggestion submitted successfully and no Return event was used. |
| Channel results | The conversation URL stayed at `/client/<team>/<conversation>`. The channel search appeared in a secondary pane headed by `p-explorer_header--search_in_channel`. Its virtual list exposed `loading` during retrieval and `empty-results-state` on no matches. A populated pane exposed View Search. |
| Full results | View Search changed the URL to `/client/<team>/search` and retained the active In filter. The results were in an `AXContentList` in the search sidebar. The Sources control was `search-filters-sources-filter`, with Messages, DMs, Files, People, Channels and Canvases in generated menu slots. In, From, Has link and Threads were separate controls. The sort menu at `search-filter-sort-filter` showed Most relevant selected, followed by Newest and Oldest. Scrolling the last row did not add results for the one-message fixture. Multi-page live behavior remains unverified. |
| Message identity | The result row had a generated DOM identifier. The timestamp link’s `AXURL` carried the conversation and timestamp in `/archives/<conversation>/p<timestamp>`. The full result’s timestamp link acknowledged a press and did not navigate. The indexed row’s semantic action menu exposed Jump, which navigated to the verified result. |
| Leaving | A forced deep link to the same conversation left its secondary search pane open. The pane’s header button closed it. A channel deep link from the full results page restored the starting conversation. Reopening search after a direct pane close restored the prior query and its filter. Pressing the top-bar Clear control before leaving yielded a blank field with no filter chips on reopen. |

| Release CLI check | Outcome |
| --- | --- |
| Message fixture | One synthetic result with a verified identifier, `complete: true`, and return to the starting conversation. The three-message fixture was unavailable. |
| Files | The source preserved the In filter and returned an empty, complete result. A seeded file was unavailable, so live extraction of a file result was unverified. |
| Canvases | The source preserved the In filter and returned an empty, complete result. |
| People and Channels | The client stopped exposing the In filter after selecting either source. The CLI now returns `unsupported_destination` for these choices with a conversation filter. |
| DMs | A channel-scoped request returned `unsupported_destination`. |
| No matches | Exit 0, empty results, one page, and `complete: true`. |
| Extra quick filters | From me, Has link and Threads only each returned a complete empty result when combined individually with the notes filter and the no-hit query. |
| Result limit | One result and `stopReason: "limit"`. |
| Open result | Jump left the client in the verified conversation with the exact message rendered. |
| Unknown type | Exit 13 with the visible source choices in the error details. |
| Ctrl-C after modal open | Exit 130 and an explicit `overlay_left_open` error. A separate, locked cleanup pressed the owned backdrop and verified the restored conversation. |

The release build, all 94 fixture tests, and the diff check passed for the live run above. The cancellation follow-up verified cleanup before Accessibility mode restoration, a replacement popup left untouched, and restoration when interrupted during paging. A fixture process also received an actual SIGINT before submission and during paging.

## Release regression retest

The live checks used stock Slack 4.53.292 on main-mac with the same locked notes fixture.

| Check | Outcome |
| --- | --- |
| Scoped People and Channels | Both returned exit 13 and `unsupported_destination` before the modal-open trace. Notes remained current with no search pane. |
| Scoped Messages | 12 identified matches. The result retained the notes filter, reported `complete: true` and restored notes. |
| Scoped Files | Three file results exposed identifiers. The result retained the notes filter, reported `complete: true` and restored notes. |
| Workspace People | The signed-in fixture returned one labeled result and restored notes. The result grid exposed no user identifier, so the response had `user: null`. |
| SIGINT after modal open | Exit 130, empty stdout and clean stderr apart from debug traces. Doctor passed all eight checks. The exact notes conversation returned with no search pane. |
| SIGINT after results were ready | Exit 130 and empty stdout. Doctor passed all eight checks. The exact notes conversation returned with no search pane. |

Immediately after opening search, Slack exposed a close button that acknowledged a press and left the popup visible. Refreshing the Accessibility mode exposed the associated backdrop and changed the popup's Accessibility reference. Cleanup now verifies the same unique popup identifier and search field in the original window and location after refreshing its own Accessibility mode. The fixtures exercise interruption before the first popup snapshot, a delayed backdrop and a replacement popup with the same identifier.

Cleanup verifies that the Sources menu stays closed before reopening it to check the selected source. The People source rendered an `AXTable` with class `p-bp__grid`. Reading the name button under each row cell recovered the label and avoided duplicate cells exposed through column nodes. After one later People directory run, Slack reopened the previous scoped search pane in notes. A locked cleanup closed it through its verified header before the workspace People retest.

The combined release build, 157 Swift Testing tests, 15 XCTest tests and `git diff --check` passed on main-mac.

## Directory return

On stock Slack 4.53.292, the `bf6755d` baseline passed scoped Messages and Files, workspace People, and both SIGINT checks. The first short People directory run returned to clear notes. In two later runs, a scoped search left notes clear and People reopened the stock scoped search pane while returning success. The next search returned exit 12 with `ui_blocked` both times. The reopened pane exposed no top-bar Clear control. A locked probe verified the notes account and closed the pane through its stock header.

Directory now checks for that header on return. It presses the scoped close control only if the pane was absent on entry and before navigation back, the starting account, window and conversation still match, and no user input intervened. It leaves pre-existing panes alone and returns `overlay_left_open` when it cannot establish ownership of a pane left by the transition.

The patched build passed the original sequence and kept notes clear after the short People run. The first follow-up search returned `ui_drift` with notes still clear. On retry, four scoped search, People and read cycles succeeded, alternating Messages and Files. Each People run returned to verified notes without a secondary pane, modal or sheet.

## Positive self-DM search

Two scoped Messages searches returned one exact self-DM hit each for the synthetic send and the upload caption. The send hit matched the receipt timestamp. Both searches verified the self filter and returned to `notes`. A scoped Files search returned `13 / destination_mismatch` and left its results pane in `self`. A locked check matched the destination and closed that pane through its stock search header. The final snapshot verified `notes` with an empty composer and zero secondary panes, modals or sheets. [Self-DM write validation](write.md#live-recovery-under-the-passive-preview)

## Scoped Files transition

On stock Slack 4.53.292, the self-DM Files retest reused the existing synthetic upload and matched the exact signed-in account. The scoped pane rendered before its **View in Search** button. Expanding the pane changed the URL from the exact self-DM to the workspace’s full search view. The URL, native In control and its title stayed the same as the selected source changed from Messages to Files. Slack exposed the generated filename and file ID. The file row itself had no conversation ID.

With a query that never acquired a full-search launcher, Slack showed only the scoped empty pane. Its Back and Close buttons shared icon classes, with Back nested under the header. The fixed CLI returned `13 / unsupported_destination`, closed the direct Close control and restored `notes`.

Full self-scoped search could hide and later remount its pane. A direct self-DM link from full search landed on Slack’s DMs index during the probe. Cleanup returns through the verified starting conversation before revisiting the scoped anchor when appropriate. It closes the pane only after matching the submitting window and anchor and checking for intervening input. The fixtures exercise a late launcher, a stale pane during expansion, a missing or changed In filter, and a pane that predates submission.

The scoped Notes Files retest returned three identified files. A self-scoped Messages search matched the existing synthetic message’s timestamp. The following People directory run and in-place read both succeeded and left `notes` with an empty composer and no stale panes, modal or sheet. The scoped sort menu uses its original control for dismissal when Slack omits its backdrop.

Self-scoped Jump reached the exact synthetic message, and a separate rendered read matched its timestamp. A dry run confirmed the signed-in account and empty self-DM composer. After Jump, Slack remounted the old scoped pane on a later self-DM visit. The next search refused to close that pre-existing pane. The investigation closed the pane using its verified header before continuing in `notes`.

## Remaining live validation in priority order

Run these checks in an exclusive main-mac Slack session after upload validation. Use the existing verified notes and self-DM aliases and record only counts, status codes, and verification outcomes.

| Priority | Fixture and check | Expected evidence |
| --- | --- | --- |
| 1 | Take the generated file name and unique search token from upload validation. Reuse three approved synthetic messages containing that token in notes. Search for it with `--in notes` and then with `--type files --in notes`. | The three messages and the uploaded file appear in their respective searches. Compare their structural IDs with those observed at seeding and verify return to the starting conversation. |
| 3 | Search the DMs source for the self-DM token and the Canvases source for an approved synthetic canvas shared in notes. Search Channels for a known synthetic channel fixture at workspace scope. | Record positive results with structural IDs or explicit nulls. Leave any source pending until its fixture is available. |
| 4 | Use a synthetic result set large enough to cross a client page boundary. Search within the designated conversation with small `--max-results` and `--max-pages` bounds, then repeat past the boundary. | Record whether the last-row action reveals another page, the true stop reason, ordering, duplication, and restoration. Report a stall or client-imposed limit if the end cannot be verified. |
| 5 | Interrupt a notes search during a page transition once a multi-page fixture is available. | Exit 130, no results printed, and `doctor` plus an exact starting-conversation check succeed after cleanup. Record an explicit cleanup error if the client blocks restoration. |
