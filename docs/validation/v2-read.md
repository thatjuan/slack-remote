# Web API read validation

Ran on main-mac on 2026-11-28 with the ad hoc release installed by `scripts/install.sh`. SlackRemote.app had active sessions for GIF Monger, Altumo and Jaramillo. The config restricted writes to `slack-remote` and `juan`. The GIF Monger test channel initially contained one join event. The live run seeded 19 top-level fixture messages and one reply there, plus one fixture in the self-DM. Each synthetic message began with `slack-remote test`. Altumo and Jaramillo were read-only.

| Check | Result |
| --- | --- |
| GIF Monger `read --dest slack-remote --limit 20` | Returned 20 unique timestamps in chronological order, from `1795842464.566199` to `1795897006.648519`. They matched the existing join event and Slack's 19 write receipts in order. Stock Slack desktop was signed in to Altumo, so the GIF Monger comparison used the Web API receipts. |
| Thread read | At `1795896982.958939`, returned the parent first and its sole reply `1795896983.141399`, with `replyCount: 1` on the parent. |
| Exclusive timestamp | `--since 1795896982.958939` returned the 18 newer top-level fixtures and reported `boundary`. `--limit 1` returned the latest timestamp and reported `limit`. |
| Unread state | Stock Slack desktop showed two unread messages on an Altumo group DM before a read. Reading its newest message left the badge at two and the desktop on the same conversation it already showed. |
| Channel lists | GIF Monger returned 50 memberships and 17 public channels. All 13 public membership IDs appeared in the public directory. Altumo returned 114 memberships across two cursor pages, including the group DM checked in Slack desktop. Jaramillo returned five memberships. |
| Members | `members --dest slack-remote` returned Juan with the same user ID as the account and people results. The GIF Monger self-DM returned one member. The Altumo group DM returned three. |
| People | `people --team T02R8SSJGCU --limit 50` reached the end after 20 eligible users. The signed-in user had the expected ID and display name. |
| File search | The existing synthetic upload in Altumo returned one file match both at workspace scope and with its conversation ID. |
| Search pagination | GIF Monger `search --query test --sort timestamp --limit 120` returned 120 unique permalinks in descending timestamp order across two pages. Slack reported 536 matches. |

## Search modifiers

| Request | GIF Monger result |
| --- | --- |
| `--in slack-remote` → `in:#slack-remote` | The query `slack-remote test` found 21 matches workspace-wide and 20 with the channel filter. All 20 had conversation ID `C0CMFR1S2AZ`. |
| `--in juan` → `in:@j` | The same query found only the self-DM fixture. Slack returned the handle `j` from `users.info`. |
| `--from-me` → `from:<@U05V0U3LA7L>` | The query `test` returned 82 matches, all from the signed-in user. Without the modifier the first 100 matches included 49 from other users. |
| `--has-link` → `has:link` | The fixture query went from 20 matches to the one linking to `example.org`. |
| `--threads-only` → `is:thread` | The fixture query returned only the parent and reply. Combining the workspace filters with the reply's unique term found only that reply. |

Each live search showed an empty warnings array. Swift Testing covers the `filtered_<n>` warning with mismatched Slack results.
