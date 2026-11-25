# Read validation

On main-mac, `swift build -c release`, `swift test`, and `git diff --check` passed. Swift Testing reported 27 tests in five suites, including nine reader tests. The release CLI displayed `read --help` and returned status `64` for either destination flag on its own, `--user` without a destination, and a negative limit.

| Live check | Outcome |
| --- | --- |
| 1. Compare the newest message, rendered count, and inherited sender with Slack on screen. | Skipped. No live session was scheduled. |
| 2. Check field coverage for links, emoji, reactions, attachments, and messages posted by apps. | Skipped for the same reason. Reaction label shape and inline emoji exposure remain unverified. The reader takes text from `AXStaticText` values and omits inline images. |
| 3. Record `skippedItems` and inspect any skipped items. | Skipped. No live count was collected. The fixtures cover a matching item without a body. |
| 4. Compare the conversation, scroll position, and frontmost application before and after the read. | Skipped. No live session was scheduled. |
| 5. Navigate from another conversation and verify the disposable destination and route. | Skipped. `SLACK_REMOTE_TEST_TEAM` and `SLACK_REMOTE_TEST_CHANNEL` were unavailable. |

## History anchor recovery

On main-mac with stock Slack 4.53.292, the release CLI used the project lock and the private fixture config. Separate rendered reads checked the starting message before and after each history run in the verified `notes` conversation.

| History run | Messages | Snapshots | Stop reason | Starting message rendered afterward |
| --- | --- | --- | --- | --- |
| One page | 8 | 1 | `limit` | Yes. The same eight messages remained in order. |
| Multi-page | 8 | 4 | `stalled` | Yes. Slack rendered 14 messages afterward. |
| Deeper multi-page | 15 | 5 | `stalled` | Yes. Slack rendered 10 messages afterward. |

All three commands exited `0` with `complete: false`, `scrollRestored: true`, ordered unique messages, and one skipped item each. The multi-page runs used `--allow-partial`. The comparison checked message identity in the rendered list. Exact viewport position was unmeasured.

The locked self-DM preflight verified the client URL, selected sidebar row, and signed-in self-DM marker. Slack showed the recognized attachment preview. The readable editor was blank and showed zero pending files, so the existing-draft check stopped before history. The preflight returned to verified `notes` with zero secondary panes and zero blocking overlays. A separate `doctor` run passed all eight checks.

The merged release passed `swift build -c release`, 153 Swift Testing tests, 12 XCTest cases, and `git diff --check`. The fixtures cover return to a virtualized anchor, a missing spacer, a stalled reverse scroll, and a thread change during restoration.
