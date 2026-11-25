# v1.0 release validation

The release is blocked by the failed matrix rows below. Main-mac ran stock Slack 4.53.292 on macOS 27.2.1 with Swift 6.4.2 on 2026-11-24. The installed CLI reported 1.0.0. The run used the integrated code after the upload merge.

The run used a private test configuration and the shared project lock. Setup ran `doctor`, `whoami --save` and `dest add` for notes and self with `restrictWritesToDestinations` enabled throughout. All content changes used generated fixtures in notes. No command changed the pre-existing self draft. When the self route reproduced the interactive popup, the stock Slack channel link returned to verified notes under the same lock. [Self popup evidence](v1-foundation.md)

| # | Area | Command or action | Expected | Outcome | Note |
|---|---|---|---|---|---|
| 1 | Build | `swift test` | all tests pass | pass | `swift test` passed 146 tests in 23 suites. `swift build -c release` and `git diff --check` passed. |
| 2 | Install | `scripts/install.sh`, `slack-remote --version` | `1.0.0` | pass | Installed to an isolated prefix and to the default prefix under a disposable home. Both printed `1.0.0`. Reinstall succeeded, unrelated and symlink targets were refused, and uninstall preserved both local data directories. |
| 3 | Environment | `doctor` | every check passes | pass | The installed CLI passed all eight checks. |
| 4 | Environment | `doctor` from an ssh shell | exit 10 | pass | The SSH invocation exited `10` with `accessibility_not_trusted`. |
| 5 | Environment | `current` started 10 s before locking the screen | exit 10, `screen_locked` | skipped | No operator was available to lock and unlock the shared desktop. |
| 6 | Concurrency | two `current` at once; one with `--timeout 0.2` under a held lock | both succeed in turn; exit 14, `busy` | pass | The two commands waiting for the lock each succeeded after release. The short-timeout command returned `14 / busy` while the lock was held. |
| 7 | Recovery | Ctrl-C during `doctor`, then `doctor` | tree was restored, no marker file | pass | Sent SIGINT after doctor created its recovery marker. It exited 130. The next doctor enabled the tree again, passed and left no marker. |
| 8 | Account | `whoami` | ids present, no popup left | pass | All account fields were present and the popup was closed. |
| 9 | Account | wrong `selfDM` in config, `open --dest notes` | exit 20, `account_mismatch` | pass | The mismatched test config returned `20 / account_mismatch`. Restored the isolated config. |
| 10 | Navigation | `open --dest notes`, `open --dest self` | verified, route reported | fail | notes verified via `already_there`. self returned `12 / overlay_left_open`. The locked stock link restored notes. [Self popup evidence](v1-foundation.md) |
| 11 | Navigation | `open` with an id that does not exist | exit 13 | pass | The missing synthetic sidebar target returned `13 / destination_unreachable`. notes stayed selected. |
| 12 | Navigation | `open --dest notes` with another app frontmost | Slack does not keep focus, or `focusRestored` is true | pass | With Finder frontmost, the `sidebar_row` route verified notes and left Finder frontmost. |
| 13 | Read | `read` with no destination | matches screen, view unchanged | pass | An independent Accessibility snapshot had 9 timestamped rows. In-place read returned 8 ordered messages and reported one skipped row. The primary structure stayed the same. Visual text comparison was unavailable. |
| 14 | Read | `read --dest self --history --max-messages 50` | ordered, no duplicates, `complete` consistent | skipped | The self navigation attempt left the pre-existing interactive popup in place. The production guard prevented a verified history run. [Self popup evidence](v1-foundation.md) |
| 15 | Read | `read --dest notes --history --max-pages 1` | `stopReason: limit`, exit 0 | pass | notes history returned one ordered page with `limit` and restored scroll position. |
| 16 | Dry run | `send`, `reply`, `react`, `upload` with `--dry-run` | Slack unchanged, plan printed | pass | All four previews returned plans. A before-and-after read showed the same rendered messages and no overlays. |
| 17 | Write gate | `send --dry-run` to a conversation outside `destinations` | exit 15, `write_not_allowed` | pass | The unallowlisted synthetic target returned `15 / write_not_allowed` before navigation. |
| 18 | Draft | `draft set --dest self`, then the same text again | text in composer; `method: existing` | skipped | The self draft was protected. The notes substitute accepted the exact draft twice and returned `method: existing` on the second set. |
| 19 | Draft | `draft set` with different text | exit 15, `draft_conflict`, draft unchanged | skipped | The self draft was protected. The notes substitute returned `15 / draft_conflict`. The original text could still be cleared by exact match. |
| 20 | Draft | `draft clear` wrong text, then right text | refused; then cleared | skipped | The self draft was protected. The notes substitute refused the wrong text and cleared the matching draft. |
| 21 | Text rules | `send` with `/x`, with `+:tada:`, with `@here` | exit 15, Slack untouched | pass | The dry-run guard returned `15 / unsafe_text` for all three inputs. The notes composer stayed empty. |
| 22 | Send | `send --dest self --text "slack-remote test <n>"` | one message, `ts` matches `read` | skipped | The pre-existing self draft and blocking popup prevented a safe send. |
| 23 | Send | `send --dest notes` with `:tada:` in the text | emoji round-trips through `read` | pass | One send returned a confirmed receipt. The exact timestamp and shortcode matched one rendered post. |
| 24 | Human gate | `draft set` while typing in Slack | exit 14, `slack_in_use` | skipped | No operator was available to provide physical Slack input. The recent-input gate passed in fixtures. |
| 25 | Blocked UI | open Slack Preferences by hand, `send --dry-run`, close it | exit 12, `ui_blocked`; the tool closed nothing | pass | Opened Slack Settings with its stock menu item. The dry run returned `12 / ui_blocked` and left Settings open. Closed Settings through its verified Accessibility control. |
| 26 | Thread | `read --dest notes --thread <ts>` | root first, replies in order | pass | notes thread read returned two ordered entries with the root first. |
| 27 | Thread | `reply` on a test message; again with another thread open | one reply in the requested thread each time | pass | Both notes replies returned a confirmed receipt and rendered once in the requested thread. The second started with another thread open. |
| 28 | Reaction | `react --emoji tada`, then again | one reaction; `alreadyReacted: true` | pass | The first command added one reaction. The second reported `alreadyReacted: true`. The target still showed one reaction. |
| 29 | Reaction | `react` with an unknown short name | failure, picker closed, nothing added | pass | The unknown name returned `15 / unsafe_text`. The picker closed and the reaction list was unchanged. |
| 30 | Listing | `channels`, `channels --max-items 5` | both test destinations present; `limit` | pass | The sidebar returned 32 conversations including notes and self. The capped run returned five with `limit`. |
| 31 | Listing | `members --dest notes`, `members --dest self` | count equals `expectedCount`; exit 13 | pass | notes returned one member with `expectedCount: 1`. self returned `13 / unsupported_destination` before navigation. |
| 32 | Listing | `channels --source browser`, `people`, where built | plausible counts, starting view restored | fail | The browser returned `12 / overlay_left_open` with zero results. The People directory returned five entries in five pages with `stalled`. notes was current after both commands. |
| 33 | Search | `search --query "slack-remote test" --in notes` | seeded messages with ids, starting view restored | pass | The scoped search returned nine synthetic matches with verified identifiers and restored notes. |
| 34 | Search | the same with `--type files`, and each other available type | file found; other types return | fail | Files returned one exact generated fixture with its identifier and retained notes scope. Canvases returned empty. DMs and Channels returned the expected `13 / unsupported_destination`. Scoped People returned `12 / ui_drift`. [Source scope evidence](search.md) |
| 35 | Search | a query with no matches; `--max-results 1` | empty and complete; `limit` | pass | The no-hit query returned an empty, complete result. The capped query returned one result with `limit`. |
| 36 | Search | `--open 0` | `notes` shown with the message rendered | pass | Indexed Jump opened the generated notes message, verified independently with a rendered read. |
| 37 | Upload | `upload --dest self --file <test file>` | one message with the file, staging removed | skipped | The protected self draft and interactive popup prevented a safe upload. [Upload validation](upload.md) |
| 38 | Upload | `upload --dest notes --thread <ts> --file <test file> --text …` | file and text in the thread only | pass | The confirmed receipt matched one attachment and caption in the notes thread. The primary message list did not contain that receipt. Staging was removed. |
| 39 | Upload | zero-byte file, directory, missing path | exit 15, `file_rejected` | pass | The zero-byte file, directory and missing path each returned `15 / file_rejected`. |
| 40 | Upload | `upload` with a test draft present | exit 15, draft unchanged | pass | Upload returned `15 / draft_conflict`. Exact-match clear verified the generated draft was preserved. |
| 41 | Leftovers | after the run: `doctor`, `inspect --scope window` | no popup, no sheet, no thread pane left by the run, tree off | pass | Doctor and window inspect passed. The next doctor enabled the tree afresh. Verified notes with no blocking popup, sheet, secondary pane or recovery marker. |
| 42 | Scripting | `scripts/check-json.sh` and the worked example in `docs/scripting.md` | valid JSON throughout, example completes | fail | The worked example returned a confirmed reply, verified by a thread read. The JSON checker stopped at a CLI error `12 / overlay_left_open`. Fixture checks accepted valid JSON, rejected invalid and duplicate documents, and propagated a command failure. |
| 43 | Package | `scripts/package.sh`, unzip elsewhere, run `doctor` from the unzipped binary | zip and checksum produced, binary runs | pass | The archive checksum and both signatures verified. The arm64 slice extracted to an isolated directory passed all eight doctor checks. |

## Additional observations

- SIGINT just after search modal open. The process exited 130 with `overlay_left_open` and empty stdout. Its popup remained visible until a locked recovery closed the owned stock Slack control and verified notes.
- SIGINT later in search. SIGINT 1.4 seconds after the modal-open trace exited 130 with empty stdout. notes returned with no overlays. The exact search phase was unobserved.
- Additional search sources. The additional scoped People and workspace-level Channels and People attempts returned `12 / ui_blocked` while a scoped search pane remained open. The owned pane was closed through its verified header control.
- Multi-page notes history. notes history returned 29 ordered, unique messages in ten snapshots. It stopped with `stalled`, `complete: false` and `scrollRestored: false`.
- Multi-page notes search. The expanded notes search returned 12 hits with `end_of_list` in one snapshot. The available synthetic fixtures did not exercise a second results page.
- Browser rerun. The five-item browser run also returned `12 / overlay_left_open` with zero rows.
- Final client state. Verified notes had an empty composer, no popup, sheet or secondary pane, and no tree recovery marker.
- The release payload is universal `arm64` and `x86_64`. Both slices target macOS 14.0 and have linker-generated ad hoc signatures. Main-mac executed the arm64 slice and verified both slices statically. The x86_64 launch was unavailable on this host.
