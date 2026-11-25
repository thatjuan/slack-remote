# slack-remote: plan for the complete CLI

The second milestone, ready to file. It extends the v0.1 plan in `planning/` to the full product: threads, reactions, emoji, history, listing, search, upload, account checks, dry runs and a release. Nothing here is filed yet and nothing is implemented by this branch.

## What to file and what to update

Milestone to create: `v1.0: Complete Slack desktop CLI`, with the contents of [`milestone.md`](milestone.md) as its description.

| Plan label | Action | File | Title |
|---|---|---|---|
| 1, 2, 3 | Comment on each filed issue | [`amendments-to-1-3.md`](amendments-to-1-3.md) | unchanged |
| 4 | Update the filed optional issue: new title, new body, add to the v1.0 milestone, remove any "optional" label | [`issues/04-threads-reactions-emoji.md`](issues/04-threads-reactions-emoji.md) | Thread read and reply, reactions, and emoji in messages |
| 5 | File new | [`issues/05-foundation-overlays-paging-history-accounts.md`](issues/05-foundation-overlays-paging-history-accounts.md) | v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run |
| 6 | File new | [`issues/06-list-channels-members-people.md`](issues/06-list-channels-members-people.md) | List channels, conversation members and the people directory |
| 7 | File new | [`issues/07-native-search.md`](issues/07-native-search.md) | Native Slack search: messages, files and other result types, with filters and navigation to a result |
| 8 | File new | [`issues/08-file-upload.md`](issues/08-file-upload.md) | Upload a file to a verified channel, DM or thread |
| 9 | File new | [`issues/09-release-and-validation-matrix.md`](issues/09-release-and-validation-matrix.md) | Installable v1.0 release and the full validation matrix on main-mac |

Each issue file begins with an HTML comment holding the title, then a note mapping plan labels to titles. The bodies refer to each other by plan label ("issue 5"). GitHub will assign different numbers if pull requests have used some, so the note stays in the body; replace labels with real numbers after filing if you prefer.

```sh
M='v1.0: Complete Slack desktop CLI'
gh api repos/thatjuan/slack-remote/milestones -f title="$M" -F description=@planning/next/milestone.md

# Issue 4: update in place. Replace <N> with its GitHub number.
gh issue edit <N> --repo thatjuan/slack-remote --milestone "$M" \
  --title 'Thread read and reply, reactions, and emoji in messages' \
  --body-file planning/next/issues/04-threads-reactions-emoji.md

for f in 05-foundation-overlays-paging-history-accounts 06-list-channels-members-people \
         07-native-search 08-file-upload 09-release-and-validation-matrix; do
  title=$(sed -n '1s/^<!-- title: \(.*\) -->$/\1/p' "planning/next/issues/$f.md")
  gh issue create --repo thatjuan/slack-remote --milestone "$M" --title "$title" \
    --body-file "planning/next/issues/$f.md"
done
```

The amendments go on issues 1 and 3 as comments, one section each. If those issues' pull requests have merged, no action is needed beyond filing issue 5, which applies whatever is missing.

## Why this is the issue set

Six issues cover the remaining product. Each is one coherent unit a single implementer finishes in one pass, and the split follows what can run at the same time without two workers editing one file.

- Issue 5 holds everything shared: closing popups safely, the bounded pager, account and destination checks, dry runs, and the `inspect` command that later probes use. History is in it because it is the first user of the pager.
- Issue 4 keeps threads, reactions and emoji together. All three target a single message through the same context menu.
- Issues 6 and 7 are read-only and independent of each other and of issue 4.
- Issue 8 needs the thread scope from issue 4 and edits the same composer and sender files, so it follows issue 4.
- Issue 9 packages the result and runs one matrix over all of it.

## Dependencies and waves

```
v0.1:  1 ──▶ 2 ──▶ 3                         (unchanged, waves 1 to 3)

v1.0:  3 ──▶ 5 ──┬──▶ 4 ──▶ 8 ──┐
                 ├──▶ 6 ────────┼──▶ 9
                 └──▶ 7 ────────┘
```

| Wave | Issues | Notes |
|---|---|---|
| 1 to 3 | 1, 2, 3 | The MVP plan is unchanged. |
| 4 | 5 | Alone. Applies the amendments if they are missing. |
| 5 | 4, 6, 7 | Code and unit tests in parallel, each in its own worktree. |
| 6 | 8 | After issue 4 merges. |
| 7 | 9 | After everything merges. |

Live validation is never parallel. There is one Slack client on main-mac, and two tools driving it interfere: during planning, a probe and the MVP workers cleared each other's accessibility tree and moved each other's view. In wave 5 the coordinator gives one worker at a time the turn to run live steps. A worker without the turn builds, runs `swift test`, and waits. Probes use `slack-remote inspect`, which holds the same lock as every other command.

## File ownership

No two issues in the same wave touch the same file. Issue 5 registers stub commands for the later issues, so none of them edits `Main.swift`, and each later issue adds its own `Locators+<Area>.swift` and its own `docs/commands/` files.

| Issue | Creates | Modifies |
|---|---|---|
| 5 | `Overlays`, `VirtualListPager`, `History`, `Config`, `Account`, `DryRun`, `Inspector` in `SlackRemoteCore`; commands `Whoami`, `Dest`, `Inspect` and the seven stubs; their tests; `docs/commands/` for existing commands; `docs/validation/v1-foundation.md` | `Main.swift`, `CommandSupport.swift`, `Commands/{Open,Read,Draft,Send}.swift`, `UINode.swift`, `AXNode.swift`, `RemoteError.swift`, `Locators.swift`, `FakeNode.swift`, `README.md`; for the amendments, `Navigator`, `SlackApp`, `SlackWindow`, `Sender`, `Composer` |
| 4 | `MessageTarget`, `ThreadView`, `Reactions`, `Locators+Threads`; commands `Reply`, `React` (replacing stubs); tests; `docs/commands/{reply,react}.md`; `docs/validation/threads-reactions.md` | `Commands/Read.swift`, `Composer.swift`, `Sender.swift`, `MessageReader.swift`, `MessageText.swift`, `Inspector.swift`, `docs/commands/{read,send}.md` |
| 6 | `SidebarList`, `MemberList`, `Directory`, `NativeMenu`, `Locators+Directory`; commands `Channels`, `Members`, `People` (replacing stubs); tests; docs; `docs/validation/listing.md` | nothing |
| 7 | `SearchModal`, `SearchResults`, `Locators+Search`; command `Search` (replacing stub); tests; docs; `docs/validation/search.md` | nothing |
| 8 | `FileStaging`, `FilePanel`, `PendingFile`, `Uploader`, `Locators+Upload`; command `Upload` (replacing stub); tests; `scripts/make-test-file.sh`; docs; `docs/validation/upload.md` | `Composer.swift`, `Sender.swift`, `UINode.swift`, `AXNode.swift`, `Overlays.swift` |
| 9 | `Version.swift`, `scripts/{install,uninstall,package,check-json}.sh`, `docs/scripting.md`, `docs/validation/matrix.md` | `Main.swift`, `README.md`, `.gitignore` |

## Routes, and where each stands

[`evidence.md`](evidence.md) has the detail. "Observed" means the structure and the action were seen working on Slack 4.53.292 during planning, without any content being changed.

| Capability | Route | Status |
|---|---|---|
| Navigate to a channel, private channel or DM | `slack://channel` link, verified by web area URL and selected sidebar row | Observed for `G…` and `D…` ids |
| Read history | `AXScrollToVisible` on the oldest rendered message, repeated within bounds | Observed. The start-of-conversation marker is not; issue 5 records it. |
| Act on one message | `AXShowMenu` on the message item, then a menu item found by class | Observed, including closing the menu |
| Open, verify and close a thread | Menu item, then pane item ids carrying conversation id and root timestamp, then the pane's close button | Observed for an empty thread |
| Reply in a thread | The pane's own editor and send button, with issue 3's gates | Structure observed; the write is issue 3's method |
| Add a reaction | Menu item, then the picker cell with id `emoji-picker-<short_name>` | Observed up to the press. Emoji name on an existing reaction is not; issue 4 has a rule for either outcome. |
| List sidebar conversations | Sidebar rows with ids | Observed. Paging the sidebar is not; issue 6 probes it. |
| List members | Details modal, items with user ids | Observed |
| Channel browser, people directory | Native Go menu items, found by key equivalent | Entry points observed; the views are not. Issue 6 probes them and builds a source only if rows carry ids. |
| Signed-in account | Self-DM row id in the sidebar; user id in the search modal's `from` filter id | Observed |
| Search | Search modal, query field, filter toggles with ids | Opening, filters and closing observed. Typing, submitting and the results view are not. Issue 7 probes them in order. |
| Upload | Attach menu, native file sheet, file chosen by URL | Menu, sheet and cancel observed. Selecting a file and the pending-file element are not. Issue 8 probes them, with a pasteboard route as the fallback. |

Routes that were ruled out, with the observation:

- Sidebar `AXRow` press: returns success, does nothing. The inner group is the target.
- Hover toolbar by focus: setting `AXFocused` on a message does not reveal it. The context menu replaces it.
- `AXCancel` on Slack menus: returns success, closes nothing. The overlay press replaces it.
- Typing a path in the file sheet: there is no path field, and "Go to folder" needs a keystroke.
- Handing Slack a file from outside: `Info.plist` declares no general document type, service or share extension.
- Thread identity from the URL: the URL does not change when a thread opens. Pane item ids replace it.

## Scope stated honestly

- History is paged through the client within bounds the caller sets (default 200 messages, hard cap 2000 per call). The result says whether it reached the caller's boundary, the start of the conversation, a limit, or fell short.
- Rendered and live: every read is a snapshot with a timestamp. There is no follow mode. A message arriving mid-read is included if the client rendered it.
- Search returns what the client's search returns, in its order, with the excerpt it renders. Complete means the end of the client's list for that tab.
- Opening a conversation or thread marks it viewed, as when a person opens it. Commands that only read without navigating change nothing.
- Listing covers what the client shows the signed-in user. A source whose rows carry no id is not built.
- One file per upload. No edit or delete of messages, no reaction removal, no scheduled sends, no canvases, huddles or workflows.

## Decisions and inputs needed

- Juan, only if issue 7's probe finds no semantic submit for a search query: whether one Return key sent with `AXUIElementPostKeyboardEvent` to Slack, while the query field is verified to hold focus, is acceptable. It is an Accessibility API call and not a coordinate click, but it is a key event, which the project's boundaries exclude today. Without a submit route, search cannot ship and issue 7 stays open.
- The two test destinations as saved destinations named `notes` and `self` in `~/.config/slack-remote/config.json` on main-mac. The config file is outside the repository; ids never go into the repository.
- Seeded test content in `notes`, placed by hand before waves 5 and 6: a message with a reply, a message with a reaction, a message with an emoji, three messages containing `slack-remote test`, and one small text file.
- A schedule that keeps other Slack-driving work off main-mac while a worker has the live-validation turn.

## Coordination note from planning

The planning probes for this milestone navigated the main-mac Slack client between the two designated conversations while MVP implementation workers were validating against the same client. Each probe returned Slack to the conversation it found, and every popup it opened was closed, but the two activities did disturb each other: trees vanished mid-run on both sides. If an MVP validation step failed with a missing tree or an unexpected conversation between about 21:05 and 21:25 on 2026-11-24, rerun it before treating it as a defect.
