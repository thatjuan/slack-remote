The complete `slack-remote` CLI: everything in v0.1, plus thread read and reply, reactions, emoji in messages, message history, channel and member listing, native Slack search, file upload, account checks, dry runs, and an installable release.

It keeps v0.1's method. The tool drives the stock Slack desktop client in the user's logged-in macOS session through Slack's documented `slack://` links and the macOS Accessibility API: reads, attribute writes, and semantic actions such as press, show menu and scroll to visible. It calls no Slack endpoint, reads no token, injects nothing into Slack, sends no synthetic mouse or keyboard event, and never clicks by coordinates.

What v1.0 adds:

- `read --history` pages back through a conversation within stated bounds; `read --thread` reads a thread.
- `reply` posts into a thread verified by conversation id and root timestamp. `react` adds a reaction chosen by exact emoji short name and never removes one.
- `channels`, `members` and `people` list conversations and people with their ids.
- `search` runs the client's own search for messages, files and the other result types it shows, with conversation and sender filters, and can open a message result.
- `upload` sends one local file to a verified conversation or thread through Slack's file panel, selecting the file by its URL.
- `whoami`, saved accounts and named destinations: writes check the signed-in account and can be restricted to listed destinations.
- `--dry-run` on every writing command, and `inspect` for structure-only diagnostics.

Rules that hold across all of it:

- Every write is gated on the exact team and conversation ids, and the message or thread id where one applies, read immediately before the action.
- Every list result says whether it is complete and why it stopped. A shortfall the caller did not ask for is an error, not a shorter list.
- A command closes every popup, pane or sheet it opened, or reports that it could not. It never closes one it did not open.
- Final controls are pressed once and never retried. An outcome that cannot be confirmed is reported as unconfirmed.
- The tool reports what the Slack client renders and returns. History and search are bounded views of the client, not exports.

Three features start with a short probe because part of their route has not been observed: submitting a search query, selecting a file inside the file panel, and reading the emoji name from an existing reaction. Each issue states the evidence, the probe, and what happens if the route does not exist. Search has one possible blocker that needs Juan's decision: if the client offers no semantic way to submit a query, the only remaining route is a single Return key sent through the Accessibility API.

Done when issues 4 to 9 are merged and the 43-row validation matrix in the release issue has been run on main-mac with no failed row. Live writes during validation go only to `#juannotes` and the signed-in user's own DM, with synthetic text and generated files, and never touch a draft the tests did not create.
