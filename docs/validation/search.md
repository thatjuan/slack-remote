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

The release build, all 94 fixture tests, and the diff check passed for the live run above. The cancellation follow-up verified cleanup before Accessibility mode restoration, a replacement popup left untouched, and restoration when interrupted during paging. A fixture process also received an actual SIGINT before submission and during paging. The updated signal path awaits a live retest.

## Remaining live validation in priority order

Run these checks in an exclusive main-mac Slack session after upload validation. Use the existing verified notes and self-DM aliases and record only counts, status codes, and verification outcomes.

| Priority | Fixture and check | Expected evidence |
| --- | --- | --- |
| 1 | Take the generated file name and unique search token from upload validation. Reuse three approved synthetic messages containing that token in notes. Search for it with `--in notes` and then with `--type files --in notes`. | The three messages and the uploaded file appear in their respective searches. Compare their structural IDs with those observed at seeding and verify return to the starting conversation. |
| 2 | Use a distinct synthetic token in the verified self-DM. Search with the self alias, then repeat with `--open 0`. | The In toggle matches the saved account, and the exact self-DM message is rendered after Jump. |
| 3 | Search the DMs source for the self-DM token and the Canvases source for an approved synthetic canvas shared in notes. Search People and Channels for known synthetic person and channel fixtures at workspace scope. | Record positive results with structural IDs or explicit nulls. Confirm that People and Channels with a conversation flag still fail without returning results. Leave any source pending until its fixture is available. |
| 4 | Use a synthetic result set large enough to cross a client page boundary. Search within the designated conversation with small `--max-results` and `--max-pages` bounds, then repeat past the boundary. | Record whether the last-row action reveals another page, the true stop reason, ordering, duplication, and restoration. Report a stall or client-imposed limit if the end cannot be verified. |
| 5 | Interrupt a notes search before submission and again while reading its results. | Exit 130, no results printed, and `doctor` plus an exact starting-conversation check succeed after cleanup. Record an explicit cleanup error if the client blocks restoration. |
