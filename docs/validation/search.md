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

Nonempty live results for Files and other sources, a self-DM search, and multi-page live results remain unverified. The release build, all 94 fixture tests, and the diff check passed.
