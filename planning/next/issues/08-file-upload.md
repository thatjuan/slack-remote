<!-- title: Upload a file to a verified channel, DM or thread -->

> Plan labels used in this text. Issues 1 to 3 are the v0.1 issues: foundation with `doctor`, `current` and `open`; `read`; `draft` and `send`. Issue 4 is "Thread read and reply, reactions, and emoji in messages". Issue 5 is "v1.0 foundation: overlays, bounded paging, message history, account and destination checks, dry run". Issue 6 is "List channels, conversation members and the people directory". Issue 7 is "Native Slack search: messages, files and other result types, with filters and navigation to a result". Issue 8 is "Upload a file to a verified channel, DM or thread". Issue 9 is "Installable v1.0 release and the full validation matrix on main-mac". GitHub numbers may differ from these labels.

Add `slack-remote upload`, which attaches one local file to the composer of an exactly verified conversation or thread and sends it, with an optional message. The file is chosen through Slack's own on-screen file panel, selected by its file URL and never by position on screen.

Depends on issues 1, 2, 3, 5 and 4. Use `UINode`, `Locators`, `SlackWindow.verify`, `verifyThread`, `Navigator`, `Composer`, `Sender`, `MessageReader`, `Overlays`, `Account`, `RemoteError` as they are. The hard boundaries from issue 1 apply: Accessibility reads, attribute writes and semantic actions; no Slack API or upload endpoints; no synthetic keyboard or mouse events; no coordinate-based clicks.

## What was observed on the real client

Slack 4.53.292, structure only. No file was attached during planning.

- The composer's Attach control is the `AXPopUpButton` with class `c-wysiwyg_container__button--shortcuts`. The primary view and the thread pane each have one.
- Pressing it opens an `AXMenu` with class `c-menu__items` inside a `ReactModal__Content` popup. It has four `AXMenuItem` nodes with the shared class `c-menu_item__button` and ids `menu-<n>-0` to `menu-<n>-3`. The fourth, `menu-<n>-3`, is "Upload from your computer". No class tells the items apart.
- Pressing the fourth item opens a native `AXSheet` on the Slack window, containing a sidebar `AXOutline`, an `AXBrowser`, an `AXSearchField` with a settable value, a location `AXPopUpButton`, and `Cancel` and `Open` buttons.
- The sheet has no field for typing a path. Reaching "Go to folder" needs a keystroke, which this project does not send.
- `AXPress` on `Cancel` closed the sheet and left the composer empty.
- Slack's `Info.plist` declares one document type, `slacktoken`, and no services or share extension. There is no documented way to hand Slack a file from outside.
- The native Edit menu has a Paste item with key equivalent `V`.

Not observed: selecting a file inside the sheet, what the composer shows for a pending file, and how a pending file is removed.

## Step 1: find the selection route

Use `slack-remote inspect --scope sheet` (add the scope's native walk if issue 5's `inspect` covers web nodes only) and a generated file. Work in the `self` destination with an empty composer. Never press send in this step; remove the pending file or cancel the sheet at the end of each attempt. Record the answers in `docs/validation/upload.md`.

Staging: copy the file to `~/Downloads/slack-remote-upload-<UUID>/<original name>`. The unique directory makes the file easy to find and the copy protects the original; the directory is deleted when the command ends.

Route A, the file panel:

1. Which attribute of a row in the sheet's browser or outline holds the file URL. `AXURL` is expected; `AXFilename` is the fallback. Add a `url` read to `AXNode` for native nodes if needed.
2. How to reach the staging directory: find the sidebar row whose `AXURL` is the Downloads folder and set `AXSelected` to true on it (or set the outline's `AXSelectedRows`); then the browser row whose `AXURL` is the staging directory, then the file row. Record which writes take effect and whether a directory row must be opened with `AXPress`, `AXOpen` or by selecting it.
3. Alternative within the sheet: set the search field's `AXValue` to the UUID and record whether results appear without a key press and whether a result row carries the file's `AXURL`.
4. Whether `Open` becomes enabled once exactly the staged file is selected, and whether `AXPress` on it closes the sheet.

Route B, only if no part of route A can select the file by URL: put the staged file's URL on the general pasteboard with `NSPasteboard.writeObjects([url as NSURL])`, set `AXFocused` on the composer, and press the native Edit menu's Paste item, found by `AXMenuItemCmdChar` `V` with modifiers `0` using `NativeMenu.press` from issue 6 (copy that function here if issue 6 has not merged). Save the pasteboard's previous items first and restore them afterwards. Record whether a pending file appears.

If neither route attaches the file, stop and report on this issue with the recorded structure. Do not send key events and do not post a `CGEvent`.

Then, with a file pending:

5. The pending-file element in the composer: its locator, where the file name is, and its remove control.
6. The send button is enabled with a pending file and an empty editor. This is the `pendingContent` state from issue 3.
7. Removing the pending file returns the composer to `empty`.
8. How the Attach menu's upload item can be identified without relying on position alone. Check each item for a key-shortcut child (`c-menu_item__shortcut`) or an icon class. If nothing distinguishes it, the locator is "the last of exactly four items", and a different count is `ui_drift`.

## Command

```
slack-remote upload --dest <NAME> | --team … --channel …
    --file <PATH> [--text <TEXT>] [--thread <ROOT_TS>] [--also-send-to-channel]
    [--max-size <BYTES>] [--allow-broadcast] [--dry-run] [--interrupt]
```

File checks, before Slack is touched, failing with `file_rejected` and a reason:

- The path exists, is a regular file after resolving symlinks, and is readable.
- Its size is above zero and at most `--max-size`, default 50 MB, hard ceiling 1 GB.
- Its name has no path separator or control character and does not start with a dot.

`--text` follows issue 3's text rules.

Steps:

1. Preflight, lock, tree session, overlay check, human-in-use gate, navigation, `Account.verify`, write restriction, as `send` does.
2. Scope: the primary view, or the pane from `verifyThread` when `--thread` is given.
3. The composer in that scope must be `empty`. A draft or a pending file already there fails with `draft_conflict`; nothing is cleared.
4. Stage the file.
5. Attach, with the route from step 1.
   - Route A: open the Attach menu and press the upload item. The menu is a popup, so use `Overlays.withModal` up to the press; the sheet replaces it. Wait for exactly one `AXSheet`. Select the staged file. Before pressing `Open`, require that the selected row's URL equals the staged file's URL exactly and that exactly one row is selected. Press `Open` once and wait for the sheet to close.
   - On any failure while the sheet is open: press the sheet's cancel button, found through the sheet's `AXCancelButton` attribute, and confirm the sheet is gone. If it will not close, throw `overlay_left_open`.
6. Verify the pending file: exactly one pending-file element in the scope's composer, and its name equals the staged file name. Zero, several, or another name: remove what was added, and fail with `write_unverified`. If removal fails, report `pendingFileLeft: true`.
7. If `--text` was given, write it with `Composer.write` and read it back.
8. Final gate, with no waiting between checks: no overlay open; `SlackWindow.verify` again; `verifyThread` again when in a thread, with the broadcast checkbox matching `--also-send-to-channel`; the pending file still verified; the editor empty or equal to the text; exactly one enabled send button.
9. Press send once. Never retry.
10. Confirm: the composer returns to `empty`, and a new message appears in the scope's list, later than the newest one seen before the press, with `hasAttachments` true and, when the file name is exposed on the message, that name. Otherwise `upload_unconfirmed`, with the same "check before retrying" guidance as `send_unconfirmed`.
11. Delete the staging directory on every exit path.

`--dry-run` runs the file checks and step 1's read-only parts, stages nothing, and prints the plan with the file name and size.

```json
"result": {
  "team": "T0AAAAAAA", "conversation": "D0CCCCCCC", "thread": null,
  "file": { "name": "slack-remote-test.txt", "bytes": 42 },
  "route": "deep_link_channel", "attachMethod": "file_panel",
  "sent": true, "ts": "1700000000.000400"
}
```

One file per invocation. Several files, drag and drop, and uploads from other sources in the Attach menu are out of scope.

## Failure and recovery

- Before `Open` is pressed, a failure leaves Slack as it was: menu closed, sheet cancelled.
- After the file is pending, a failure removes the pending file through its remove control when that is verified to work, and otherwise reports `pendingFileLeft: true`. Text the command wrote stays as a draft and is reported with `draftLeft: true`.
- `upload_unconfirmed` is terminal. The file may have been sent.
- Route B always restores the pasteboard, including on failure.

## Files

Replace the stub `Sources/slack-remote/Commands/Upload.swift`.

Create: `Sources/SlackRemoteCore/{FileStaging,FilePanel,PendingFile,Uploader}.swift`, `Sources/SlackRemoteCore/Locators+Upload.swift`, `Tests/SlackRemoteCoreTests/{FileStaging,FilePanel,Uploader}Tests.swift`, `Tests/SlackRemoteCoreTests/Support/UploadFixtures.swift`, `scripts/make-test-file.sh` (writes a small text file with synthetic content), `docs/commands/upload.md`, `docs/validation/upload.md`.

Modify: `Composer.swift` (pending-file state details), `Sender.swift` (confirmation with attachments), `UINode.swift` and `AXNode.swift` (a `node(_ attribute:)` accessor for element-valued attributes such as `AXCancelButton`, and `url`), `Overlays.swift` (`cancelSheet`), with their tests. This issue runs alone in its wave, so no other worker edits these files at the same time.

## Tests

- `FileStagingTests`: each rejection reason; the staging directory is removed after success and after a thrown error.
- `FilePanelTests`, with a fake sheet: the row whose URL equals the staged file is selected and `Open` pressed once; a row with the same name in another directory is never selected; two selected rows press nothing and cancel; a sheet that will not close gives `overlay_left_open`.
- `UploaderTests`: a non-empty composer gives `draft_conflict` before the menu opens; a pending file with another name is removed and `write_unverified` thrown; the conversation changing before the press presses nothing; a thread root changing presses nothing; no new message gives `upload_unconfirmed`; the happy path presses send once.

## Live validation

Only in the `notes` and `self` destinations, only with files made by `scripts/make-test-file.sh`. If a destination's composer already holds a draft or a pending file, skip the steps there and report it. Record outcomes in `docs/validation/upload.md` without ids, names or message text.

1. The eight observations in step 1.
2. `upload --dry-run`: Slack does not change.
3. `upload --dest self --file <test file>`: one message with the file appears; the staging directory is gone; no sheet or popup remains.
4. `upload --dest notes --file <test file> --text "slack-remote test upload"`: file and text arrive in one message.
5. `upload --dest notes --thread <ts of a test message> --file <test file>`: the file arrives in the thread and not in the channel.
6. With a draft placed by `draft set` in the `self` destination: `upload` fails with `draft_conflict` and the draft is unchanged. Remove the test draft with `draft clear`.
7. A zero-byte file, a directory, and a path that does not exist: `file_rejected`, Slack untouched.
8. Interrupt an upload with Ctrl-C while the sheet is open, then run `doctor`: record whether a sheet remained. If it did, the signal handler must cancel the sheet; fix and repeat.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed.
- A file is attached only after the conversation, and the thread when given, were verified by id.
- The file is chosen by exact file URL. No code selects a row by index, name alone or screen position.
- Send is pressed at most once, only with exactly one pending file whose name matches.
- An existing draft or pending file in the destination is never modified.
- No sheet or popup opened by the command is left open without `overlay_left_open` being reported, and the staging directory never outlives the command.
- If route B is used, the pasteboard holds its previous contents afterwards.
- `docs/validation/upload.md` records the route that was built, why the other was not, and each live step's outcome.
