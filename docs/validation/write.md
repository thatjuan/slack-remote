# Draft and send validation

The composer spike ran on main-mac with stock Slack 4.53.292. It acquired the CLI lock and verified the destination through the team's client URL and Slack's self-DM marker. The composer started blank with the send button disabled. Slack was frontmost throughout the spike.

| Probe | Observation |
| --- | --- |
| A, focus and write `AXSelectedText` | Both calls returned success and the editor reported focus. The editor stayed blank and the send button stayed disabled for all four text forms. |
| B, write `AXValue` | For plain, two-line, and URL text, `ql-blank` cleared, send enabled, and normalized `AXValue` matched the input. The sample with stars and an emoji shortcode enabled send but failed the normalized read-back comparison. The probe stopped with that synthetic draft still present. |
| Clear with `AXSelectedTextRange` and empty `AXSelectedText` | The whole selection matched `AXValue`, and both calls returned success. The editor stayed nonblank and send stayed enabled. |
| Clear with empty `AXValue` | The editor returned to `ql-blank` and send was disabled. |

The CLI enables method B and clears through `AXValue`. It stops before the send press if read-back differs from the requested text. The spike supplied no evidence for a normalization change.

## Command checks

Fixture tests cover text refusal, composer state and write-method selection, draft conflicts, destination and dialog changes, and send confirmation. All fixtures use synthetic messages and make zero calls to Slack.

On main-mac, `swift build -c release`, `swift test` (47 tests), and `git diff --check` passed. Each of the three release commands rejected all six unsafe text forms with `unsafe_text` and status `15` before opening a Slack session. Each reported missing destination flags with status `64`.

| Live step | Observation |
| --- | --- |
| Set, conflict, and clear through the CLI | Skipped. The exact read-back of the residual synthetic draft is unavailable, and an empty verified composer has yet to be confirmed. The residual draft was left in place. |
| Draft persistence and lock contention with `open` | Skipped. The named channel did not render in the sidebar snapshot, so the second destination could not be verified. |
| Background Slack | Skipped. Slack was frontmost and the work did not change focus to create this condition. |
| Preferences dialog and recent-input gate | Skipped while the foundation follow-up used the desktop. The dialog blocking behavior passed in fixtures. |
| Send, multiline send, and send over an identical draft | Skipped until the combined navigation and message-list changes can be verified in the test destination. The composer spike made zero send presses. |
