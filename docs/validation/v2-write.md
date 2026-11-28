# Web API write validation

Ran on main-mac on 2026-11-28 with SlackRemote.app 2.0.0 installed by `scripts/install.sh`. The allowlist contained only GIF Monger’s `slack-remote` channel and `juan` self-DM. The checks preserved the earlier read fixtures and made no writes to Altumo or Jaramillo.

| Check | Result |
| --- | --- |
| Dry runs | `send`, `reply` with `--also-send-to-channel`, `react` and threaded `upload` returned plans for Juan (`U05V0U3LA7L`). A `read` before and after showed identical message arrays in the channel, thread and self-DM, including reactions. |
| Channel and self-DM sends | `read` matched Slack’s receipts `1795897299.014499` and `1795897299.517579`. |
| Thread reply | `read --thread 1795897299.014499` returned `1795897300.143989`. The channel timeline omitted that reply. |
| Broadcast reply | The thread and channel timeline both returned `1795897300.650629`. |
| Repeated reaction | Adding `:tada:` to `1795897300.143989` returned `alreadyReacted: false`. Repeating the command returned `true`. The thread showed one reaction from the signed-in user. |
| Small channel upload | The 39-byte `issue-22-small.txt` returned `F0CMN3AJMM4` and `1795897750.477599`. The channel read matched the file ID, timestamp and caption. |
| Large threaded upload | The 20,971,559-byte `issue-22-large.bin` returned `F0CM8LPACH5` and `1795897835.534699`. The thread read matched the file ID, timestamp and caption. Both files started with the output of `scripts/make-test-file.sh`. |
| Direct descriptor upload | A 39-byte fixture on the helper’s local filesystem sent to the self-DM returned `F0CMRULSC57` and `1795897862.341449`. The self-DM read matched the file ID, timestamp and caption. |
| Outside the allowlist | A send to `C067QL95R0V` returned `write_not_allowed` (15). |
| Unsafe text | `/x` gave `slash_command`, `+:tada:` gave `reaction_shortcut`, and `@here` and `<!channel>` gave `broadcast_mention`. All returned `unsafe_text` (15). |

The first URLSession attempt through `/dev/fd` timed out with a source on the mounted worktree volume. A subsequent channel read confirmed that there was no share. Uploading the same bytes from the helper’s 0600 temporary file succeeded. The helper now stages files on a different filesystem before calling URLSession and streams from `/dev/fd` for files on its local filesystem. The pre-signed endpoint accepted the anonymous requests. No 401 or 403 occurred.

## Drafts

Safari Web Inspector attached to a temporary inspectable SlackRemote build using GIF Monger’s Add Workspace window. In Juan’s self-DM, typing a fixture draft produced `drafts.create`. Editing and clearing the composer did not establish the update, delete or list requests. The composer returned to empty. The desktop app was signed in to Altumo during read validation, so this run could not verify desktop sync for the GIF Monger draft. Version 2.0 drops the draft command and its documentation.

## Automated checks

`swift build`, `swift test` and `git diff --check` passed. The tests cover preflight order, broadcast text, rejected destinations and thread timestamps, ambiguous write responses, safe 429 retries, upload completion and the `share_pending` result.
