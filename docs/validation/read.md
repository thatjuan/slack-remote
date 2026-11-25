# Read validation

On main-mac, `swift build -c release`, `swift test`, and `git diff --check` passed. Swift Testing reported 27 tests in five suites, including nine reader tests. The release CLI displayed `read --help` and returned status `64` for either destination flag on its own, `--user` without a destination, and a negative limit.

| Live check | Outcome |
| --- | --- |
| 1. Compare the newest message, rendered count, and inherited sender with Slack on screen. | Skipped. No live session was scheduled. |
| 2. Check field coverage for links, emoji, reactions, attachments, and messages posted by apps. | Skipped for the same reason. Reaction label shape and inline emoji exposure remain unverified. The reader takes text from `AXStaticText` values and omits inline images. |
| 3. Record `skippedItems` and inspect any skipped items. | Skipped. No live count was collected. The fixtures cover a matching item without a body. |
| 4. Compare the conversation, scroll position, and frontmost application before and after the read. | Skipped. No live session was scheduled. |
| 5. Navigate from another conversation and verify the disposable destination and route. | Skipped. `SLACK_REMOTE_TEST_TEAM` and `SLACK_REMOTE_TEST_CHANNEL` were unavailable. |
