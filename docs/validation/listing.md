# Listing validation

The probes ran on main-mac against stock Slack 4.53.292. Each CLI or probe invocation held the project lock. The report records structural observations and aggregate results.

| Probe | Observation |
| --- | --- |
| Sidebar | The `AXOutline` with `c-virtual_list__scroll_container` exposed 47 structural rows, including 32 conversation rows. `AXScrollToVisible` on the last rendered row succeeded and exposed zero new rows. The `addMoreChannels` marker was present before and after. Pressing the originally selected row’s scroll action restored the same set of rendered row IDs. |
| Members | The primary toolbar exposed one matching header. The details modal opened on the active Members tab, marked by `c-tabs__tab--active`. The member row’s DOM ID matched the user ID pattern. `AXScrollToVisible` succeeded and exposed zero additional rows. The close button dismissed the modal. The one-member list did not exercise a live page transition. |
| Native Go menu | The enabled items matched the `L` and `E` key equivalents with modifiers `1`. `AXPress` succeeded on both items while Slack was frontmost, but the client stayed on the starting conversation. Opening Go first and pressing the items again produced the same result. |
| Channel browser | **Add channels › Browse channels** opened the Channels tab at the workspace root URL, `https://app.slack.com/client/<team>`. The two web menu choices had the same roles and classes and generated DOM IDs. The result container was an `AXList` with `p-explorer_results__container`. Each result was an `AXGroup` with `p-explorer_results__contained-result` and `c-virtual_list__item`, a `c-channel_search_result` child, and the conversation ID as its DOM ID. The view exposed a filter toolbar and a separate pop-up control. Scrolling the last result made nine new rows render on the first page transition. Four presses raised the distinct count from 13 to 45. No reliable total or end marker appeared. |
| People directory | Selecting the People tab in the same view kept the workspace root URL. The `AXTable` with `p-explorer_grid` had `p-grid__row` rows and `p-explorer_grid__cell` cells. The cell’s `p-browse_page_member_card_entity__info` group exposed a DOM ID formed by `browse_page_member_info_` followed by the user ID. The table exposed copies of the cells through column nodes. Reading the row children yielded five distinct IDs. The view exposed filter controls. Scrolling the last card exposed zero new IDs, and the grid exposed no reliable total or end marker. |

| Command | Observation |
| --- | --- |
| `channels` | Exit 0. Returned 32 distinct conversations in one page with `complete: true` and `end_of_list`. The configured channel and self-DM had kinds `channel` and `self_dm`. One row was selected. The count matched an independent Accessibility read of the sidebar. A manual scroll count was unavailable. |
| `channels --max-items 5` | Exit 0. Returned five items, `complete: false`, and `limit`. |
| `channels --max-pages 1` | Exit 0. Returned all 32 items with `complete: true` and `end_of_list`. |
| `channels --team … --max-items 5` | Exit 0 for the current workspace. Returned five items, `complete: false`, and `limit`. |
| `members` on the configured channel | Exit 0. The returned count and `expectedCount` were both 1. The result was complete in one page. |
| `members --max-items 1` on the configured channel | Exit 0. Returned one item with `complete: false` and `limit`. |
| `members` on the configured self-DM | Exit 13, `unsupported_destination`. |
| `channels --source browser --max-items 5` | Exit 0. Returned five distinct IDs and five nonempty labels, with `complete: false` and `limit`. |
| `channels --source browser --timeout 35` | Exit 19, `partial_result`. The error envelope included 45 distinct channels in nine snapshots, `complete: false`, and `stalled`. |
| `people --max-items 3` | Exit 0. Returned three distinct IDs and three nonempty labels, with `complete: false` and `limit`. |
| `people --allow-partial --timeout 30` | Exit 0. Returned five distinct users in four snapshots, `expectedCount: null`, `complete: false`, and `stalled`. |

The commands left the starting conversation selected. Follow-up inspections found zero blocking modals and zero native sheets.

The release build, all 91 fixture tests, and `git diff --check` passed on main-mac.

## Release regression retest

The installed matrix returned `overlay_left_open` for both browser runs. Opening Browse channels closes its menu and replaces the conversation pane with the directory. The directory now verifies the menu dismissal before reading the browser and verifies the starting conversation before returning results.

The release build on stock Slack 4.53.292 returned five unique channels in one snapshot with `--max-items 5` and `stopReason: limit`. With `--timeout 35`, it returned exit 19 and `partial_result` with 45 unique channels in nine snapshots, `complete: false` and `stopReason: stalled`. Both commands restored the exact notes workspace and conversation. The fixtures also cover a failed Browse press and verify that a replacement popup stays untouched.
