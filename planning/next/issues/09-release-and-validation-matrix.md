<!-- title: Installable v1.0 release and the full validation matrix on main-mac -->

> Plan labels used in this text. Issues 1 to 3 are the v0.1 issues: foundation with `doctor`, `current` and `open`; `read`; `draft` and `send`. Issue 4 is "Thread read and reply, reactions, and emoji in messages". Issue 5 is "v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run". Issue 6 is "List channels, conversation members and the people directory". Issue 7 is "Native Slack search: messages, files and other result types, with filters and navigation to a result". Issue 8 is "Upload a file to a verified channel, DM or thread". Issue 9 is "Installable v1.0 release and the full validation matrix on main-mac". GitHub numbers may differ from these labels.

Make `slack-remote` installable and scriptable as a release, and run every command through one validation matrix on main-mac. This is the last issue of v1.0 and closes the milestone.

Depends on issues 1 to 8. It changes no command behaviour. If a matrix row fails, fix the defect in the file that owns it and note the fix in the pull request; a behaviour change beyond a defect fix goes back to the owning issue.

## Release packaging

- `slack-remote --version` prints the version from one constant, `SlackRemoteVersion.current`, set to `1.0.0`.
- `scripts/install.sh [--prefix <DIR>]` runs `swift build -c release`, copies `.build/release/slack-remote` to `<DIR>/bin` (default `~/.local`), and prints the installed path and version. It refuses to overwrite a file that is not a previous `slack-remote` binary. `scripts/uninstall.sh` removes the binary and leaves `~/.config/slack-remote` and `~/Library/Application Support/slack-remote` alone, printing their paths.
- `scripts/package.sh` builds a universal binary with `swift build -c release --arch arm64 --arch x86_64`, zips it with `README.md` and `docs/`, and writes `dist/slack-remote-1.0.0-macos.zip` and its SHA-256 next to it. `dist/` is ignored by git. The script does not tag, push or publish; the coordinator creates the GitHub release from its output.
- The binary is signed ad hoc by the linker. No Developer ID, no notarisation, no installer package.
- No CI workflow.

## Scripting contract

Write `docs/scripting.md`, the single reference a caller needs:

- Every command prints one JSON document on stdout on success and one on stderr on failure, except `inspect` and `--version`. Give the envelope and the error shape.
- The complete exit status table, one row per status, with every error code.
- The fields common to list results (`complete`, `stopReason`, `pages`) and the rule that a shortfall exits 19 unless `--allow-partial` is passed.
- What each command changes, in three groups: nothing; the view only; content.
- Rules for callers: check the exit status before parsing stdout; never retry `send_unconfirmed`, `upload_unconfirmed` or `reaction_unconfirmed` without reading the conversation first; expect `ui_drift` after a Slack update and stop; run one command at a time or rely on the lock and `busy`.
- A worked shell example that resolves a destination, reads history with `--since`, and sends a reply, using `jq` and checking each exit status.

Add `scripts/check-json.sh`, which runs each read-only command and pipes stdout through `jq -e .`, failing on the first that is not valid JSON.

`README.md` becomes: one paragraph on what the tool is, requirements (macOS 14 or later, the Slack desktop app, the Accessibility permission for the launching app, a logged-in session), install, first-run setup (`doctor`, `whoami --save`, `dest add`), a command table linking to `docs/commands/`, the limits section, and links to `docs/scripting.md` and `docs/validation/matrix.md`.

Limits to state plainly:

- The tool sees what the Slack client renders. History is paged through the client, within bounds; search returns the client's results.
- Opening a conversation or thread marks it viewed, as when a person opens it.
- One Slack client, one command at a time. Other assistive tools that toggle Slack's accessibility mode can make a command fail with `tree_unavailable`.
- Enterprise Grid, several Slack windows, and a non-English Slack are not validated. Locators do not use labels, so a non-English client is expected to work.
- Each feature that an issue's probe ruled out, with the reason.

## Validation matrix

Run on main-mac with the Slack version installed there, record the version, and write the results to `docs/validation/matrix.md` as this table with two added columns: outcome (pass, fail, skipped) and a note. Use destination names only. No ids, names of people, channel names other than the two test destinations, or message text.

Setup: `scripts/install.sh`, then `doctor`, `whoami --save`, `dest add notes …`, `dest add self …`, and `restrictWritesToDestinations` set to true for the whole run. `notes` is `#juannotes`; `self` is the signed-in user's own DM. All writing rows use only these two, with text that starts `slack-remote test` and files from `scripts/make-test-file.sh`. Before the writing rows, check both composers: if either holds a draft the run did not create, skip the rows for that destination and say so. Never clear such a draft.

Run the rows in order, one worker, with no other tool driving Slack.

| # | Area | Command or action | Expected |
|---|---|---|---|
| 1 | Build | `swift test` | all tests pass |
| 2 | Install | `scripts/install.sh`, `slack-remote --version` | `1.0.0` |
| 3 | Environment | `doctor` | every check passes |
| 4 | Environment | `doctor` from an ssh shell | exit 10 |
| 5 | Environment | `current` started 10 s before locking the screen | exit 10, `screen_locked` |
| 6 | Concurrency | two `current` at once; one with `--timeout 0.2` under a held lock | both succeed in turn; exit 14, `busy` |
| 7 | Recovery | Ctrl-C during `doctor`, then `doctor` | tree was restored, no marker file |
| 8 | Account | `whoami` | ids present, no popup left |
| 9 | Account | wrong `selfDM` in config, `open --dest notes` | exit 20, `account_mismatch` |
| 10 | Navigation | `open --dest notes`, `open --dest self` | verified, route reported |
| 11 | Navigation | `open` with an id that does not exist | exit 13 |
| 12 | Navigation | `open --dest notes` with another app frontmost | Slack does not keep focus, or `focusRestored` is true |
| 13 | Read | `read` with no destination | matches screen, view unchanged |
| 14 | Read | `read --dest self --history --max-messages 50` | ordered, no duplicates, `complete` consistent |
| 15 | Read | `read --dest notes --history --max-pages 1` | `stopReason: limit`, exit 0 |
| 16 | Dry run | `send`, `reply`, `react`, `upload` with `--dry-run` | Slack unchanged, plan printed |
| 17 | Write gate | `send --dry-run` to a conversation outside `destinations` | exit 15, `write_not_allowed` |
| 18 | Draft | `draft set --dest self`, then the same text again | text in composer; `method: existing` |
| 19 | Draft | `draft set` with different text | exit 15, `draft_conflict`, draft unchanged |
| 20 | Draft | `draft clear` wrong text, then right text | refused; then cleared |
| 21 | Text rules | `send` with `/x`, with `+:tada:`, with `@here` | exit 15, Slack untouched |
| 22 | Send | `send --dest self --text "slack-remote test <n>"` | one message, `ts` matches `read` |
| 23 | Send | `send --dest notes` with `:tada:` in the text | emoji round-trips through `read` |
| 24 | Human gate | `draft set` while typing in Slack | exit 14, `slack_in_use` |
| 25 | Blocked UI | open Slack Preferences by hand, `send --dry-run`, close it | exit 12, `ui_blocked`; the tool closed nothing |
| 26 | Thread | `read --dest notes --thread <ts>` | root first, replies in order |
| 27 | Thread | `reply` on a test message; again with another thread open | one reply in the requested thread each time |
| 28 | Reaction | `react --emoji tada`, then again | one reaction; `alreadyReacted: true` |
| 29 | Reaction | `react` with an unknown short name | failure, picker closed, nothing added |
| 30 | Listing | `channels`, `channels --max-items 5` | both test destinations present; `limit` |
| 31 | Listing | `members --dest notes`, `members --dest self` | count equals `expectedCount`; exit 13 |
| 32 | Listing | `channels --source browser`, `people`, where built | plausible counts, starting view restored |
| 33 | Search | `search --query "slack-remote test" --in notes` | seeded messages with ids, starting view restored |
| 34 | Search | the same with `--type files`, and each other available type | file found; other types return |
| 35 | Search | a query with no matches; `--max-results 1` | empty and complete; `limit` |
| 36 | Search | `--open 0` | `notes` shown with the message rendered |
| 37 | Upload | `upload --dest self --file <test file>` | one message with the file, staging removed |
| 38 | Upload | `upload --dest notes --thread <ts> --file <test file> --text …` | file and text in the thread only |
| 39 | Upload | zero-byte file, directory, missing path | exit 15, `file_rejected` |
| 40 | Upload | `upload` with a test draft present | exit 15, draft unchanged |
| 41 | Leftovers | after the run: `doctor`, `inspect --scope window` | no popup, no sheet, no thread pane left by the run, tree off |
| 42 | Scripting | `scripts/check-json.sh` and the worked example in `docs/scripting.md` | valid JSON throughout, example completes |
| 43 | Package | `scripts/package.sh`, unzip elsewhere, run `doctor` from the unzipped binary | zip and checksum produced, binary runs |

A row for a feature that an issue's probe ruled out is recorded as skipped with a pointer to that issue's validation file. A failed row blocks the release.

## Files

Create: `Sources/slack-remote/Version.swift`, `scripts/{install,uninstall,package,check-json}.sh`, `docs/scripting.md`, `docs/validation/matrix.md`.

Modify: `Main.swift` (`--version`), `README.md`, `.gitignore` (`dist/`).

## Acceptance criteria

- `scripts/install.sh` installs a working binary to the default prefix on a clean checkout, and `scripts/uninstall.sh` removes it.
- `scripts/package.sh` produces the zip and checksum, and the unzipped binary passes `doctor`.
- `docs/scripting.md` documents every command's exit statuses and the rules for callers, and its worked example runs as written.
- `docs/validation/matrix.md` holds all 43 rows with outcomes for the Slack version on main-mac, with no failed row and a reason on each skipped row.
- After the matrix run, both test destinations contain only messages, reactions and files that start with or belong to `slack-remote test` content, and no draft the run did not find there was changed.
- The repository contains no CI workflow and no private data from the workspace.
