# Draft and send validation

The composer spike ran on main-mac with stock Slack 4.53.292. It acquired the CLI lock and verified the destination through the team's client URL and Slack's self-DM marker. The composer started blank with the send button disabled. Slack was frontmost throughout the spike.

| Probe | Observation |
| --- | --- |
| A, focus and write `AXSelectedText` | Both calls returned success and the editor reported focus. The editor stayed blank and the send button stayed disabled for all four text forms. |
| B, write `AXValue` | For plain, two-line, and URL text, `ql-blank` cleared, send enabled, and normalized `AXValue` matched the input. The sample with stars and an emoji shortcode enabled send but failed the normalized read-back comparison. The probe stopped with that synthetic draft still present. |
| Clear with `AXSelectedTextRange` and empty `AXSelectedText` | The whole selection matched `AXValue`, and both calls returned success. The editor stayed nonblank and send stayed enabled. |
| Clear with empty `AXValue` | The editor returned to `ql-blank` and send was disabled. |

The CLI enables method B and clears through `AXValue`. It stops before the send press if read-back differs from the requested text. The spike supplied no evidence for a normalization change.

## Initial command checks

Fixture tests cover text refusal, composer state and write-method selection, draft conflicts, destination and dialog changes, and send confirmation. All fixtures use synthetic messages and make zero calls to Slack.

On main-mac, `swift build -c release`, `swift test` (47 tests), and `git diff --check` passed. Each of the three release commands rejected all six unsafe text forms with `unsafe_text` and status `15` before opening a Slack session. Each reported missing destination flags with status `64`.

| Live step | Observation |
| --- | --- |
| Set, conflict, and clear through the CLI | Skipped. The exact read-back of the residual synthetic draft is unavailable, and an empty verified composer has yet to be confirmed. The residual draft was left in place. |
| Draft persistence and lock contention with `open` | Skipped. The named channel did not render in the sidebar snapshot, so the second destination could not be verified. |
| Background Slack | Skipped. Slack was frontmost and the work did not change focus to create this condition. |
| Preferences dialog and recent-input gate | Skipped while the foundation follow-up used the desktop. The dialog blocking behavior passed in fixtures. |
| Send, multiline send, and send over an identical draft | Skipped until the combined navigation and message-list changes can be verified in the test destination. The composer spike made zero send presses. |

## Combined release on main-mac

The release build, all 49 tests, and `git diff --check` passed. The send fixture now requires `send_unconfirmed` with `draftLeft: true` when Slack acknowledges a press but the composer still holds text at the deadline.

| Check | Observation |
| --- | --- |
| Destination and `doctor` | The configured self-DM matched Slack's signed-in self-DM marker, the selected sidebar row, and the client URL. All eight checks passed. The web area, primary view, editor, send button, and outer message list each matched once. |
| `open` with the exact team and conversation | Exit `0`, returned the requested destination and `already_there`. The foundation follow-up had previously verified the sidebar navigation route into this self-DM. |
| `read` for the exact destination | Four ordered messages with distinct timestamps and zero skipped items. All four had text and explicit sender labels. Three had attachment markers. `--limit 3` returned the same newest three messages. |
| Sender identity | The four sender controls exposed display labels. None had a user ID as its Accessibility DOM identifier, and the rendered tree had no observed own-message class. A display label alone could not verify the signed-in sender. |
| CLI draft set, draft conflict, exact clear, and live send | Skipped. The verified composer held text. The original probe token was never recorded, so the full contents could not be matched to the probe. The existing draft was left in place, and this run made zero send presses. |
| Second destination | Skipped. The designated channel remained unresolved. |

## Self-DM write preflight

The isolated 1.0.0 install from `06b6094520c58ef597fbe96f60f663258d341384` passed all eight `doctor` checks on main-mac. In `notes`, `whoami` matched the private fixture's workspace, signed-in user, and self-DM. After opening `self`, a separate locked Accessibility snapshot matched the client URL, selected sidebar row, and signed-in self-DM marker. It found one primary message list, editor, and send control. The editor was blank, Send was disabled, and there were zero pending files or sidebar draft markers.

Slack rendered one blocking attachment preview, with zero sheets or secondary panes. The preview exposed no dedicated close or cancel control. The run left it untouched and skipped draft set, conflict and exact clear, send, upload, and the corresponding positive self-scoped search. The CLI returned to the original `notes` view. A separate snapshot verified the destination, an empty composer, and zero blocking overlays, sheets, or secondary panes.

## Live recovery under the passive preview

The follow-up used stock Slack 4.53.292 and the same private fixture on main-mac. Reselecting the exact sidebar row preserved the blank composer and reopened the preview. The stock user link also opened a profile pane. Closing that pane through its header left the composer and preview intact. The independent Accessibility snapshots matched the signed-in self marker, workspace URL, and selected row. The primary editor reported focus. The preview and backdrop did not, and the preview exposed one link, no editable value, and no dedicated dismissal control.

| Check | Observation |
| --- | --- |
| Guarded dry run | Returned `account: verified`, `atDestination: true` and `composer: empty`. The editor stayed blank with zero pending files. |
| Draft | `draft set` returned `value` and the editor read back the exact synthetic text. Repeating it returned `existing`. Setting different text and clearing with the wrong text each returned `15 / draft_conflict`. The exact clear returned `cleared: true` and the composer was empty again. The preview stayed visible throughout. |
| Send | The release from `29e67db54b7238e9422c5092991f11250049c918` returned `sent: true`. A separate CLI read found one matching message with the same timestamp. Slack closed the preview during the send and the composer was empty afterward. |
| Upload | Started from the clear self-DM after the send. The `file_paste` receipt matched the one rendered attachment and synthetic caption. A fresh snapshot verified the empty composer. |

Both write receipts matched independently rendered messages. The scoped Messages searches found the send and upload caption. The session ended in verified `notes` with an empty composer and no secondary panes, modals or sheets. [Search observations](search.md#positive-self-dm-search)
