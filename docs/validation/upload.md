# Upload validation

Main-mac, macOS 27.2.1, stock Slack 4.53.292. Live writes used generated files in the designated private channel. The probe used the command lock and captured structure without retaining Slack IDs, file names or message text.

## File picker and pending attachment

| Check | Observation |
| --- | --- |
| Sidebar and browser file identity | The sidebar `AXOutline` exposed rows and cells without `AXURL` or `AXFilename`. The initial `AXBrowser` contained no file rows. |
| Downloads navigation | Rows advertised settable `AXSelected`, and the outline advertised settable `AXSelectedRows`. There was no row that could be verified as Downloads by URL, so the probe did not select a row. |
| Search | The search control was an `AXTextField` with subrole `AXSearchField`. The staging UUID read back through `AXValue`, but the write alone produced no matching result. The semantic `AXConfirm` action displayed the search view and still did not expose a result with the staged URL. |
| Open and Cancel | Open was disabled with nothing selected. There was no `AXDefaultButton` or `AXCancelButton` value on the sheet. The titled native Cancel button accepted `AXPress` and closed the sheet. Selection and Open were exercised with fixtures. |
| Attach item | All four items used the same icon class, and two had a shortcut child. The upload item was uniquely identified by the static text under its `c-menu_item__label` group. |
| Native Paste | After the panel closed, setting and verifying composer focus and pressing the native Edit menu item with command character `V` produced one pending file. The probe restored the prior pasteboard items. |
| Pending file | The `AXGroup` with class `p-pending_file` exposed the filename as its title and description. The editor remained blank and Send was enabled. The completed file exposed an `AXButton` with class `p-multi_file_upload__file_status_btn--remove`. |
| Removal | Pressing that button after matching the pending filename returned the composer to empty. The standalone observation did not send. |

The live route was `file_paste`. The command cancels the panel before trying Paste if the panel cannot navigate or select by the exact file URL. The fixtures cover URL selection, duplicate basenames, multiple selection, cancellation and clipboard ownership.

## Live checks

| Check | Outcome |
| --- | --- |
| Dry run | Reported the generated file size, verified account and empty composer. The channel remained selected and no staging directory appeared. |
| Self-DM upload | Skipped to preserve an existing draft and recurring popover in that destination. |
| Channel upload with caption | The first command returned `upload_unconfirmed`. A follow-up read found one message with the generated caption and exact attachment name. The reader now recognizes the rendered upload classes `c-message_kit__file` and `p-message_file`. The original send was not retried. |
| Thread upload | The CLI returned `sent: true` with `file_paste`. The receipt timestamp appeared in the verified thread and was absent from the channel list. The test closed the thread pane. |
| Draft conflict | Tested in the designated channel to preserve the self-DM draft. Upload returned `draft_conflict`, and exact-text clear then removed the generated draft. |
| Invalid file types | A zero-byte file, a directory and a missing path each returned `file_rejected` before the CLI opened a Slack session. |
| Interruption | Sent SIGINT to the locked live probe after it observed the native sheet. The probe ran the shared sheet cancellation and staging cleanup, exited with status 130, and `doctor` passed. The file-panel fixture verifies cancellation before Open. |
| Final state | The designated channel was selected with an empty composer, no blocking popup or sheet and no staging directory. |
