# Foundation validation

Ran on main-mac with macOS 27.2.1, Xcode 27.2, and Slack 4.53.292.

- `swift build -c release` passed.
- `swift test` passed all 18 tests in four suites. The URL parser test covered all six examples.
- `git diff --check` passed.
- Missing destination flags, a malformed conversation ID, and a zero timeout each exited with status `64`.

| Step | Observation |
| --- | --- |
| 1. `doctor` | Exit `0`. GUI session, screen unlocked, Accessibility trust, Slack running, Slack visible, tree available, client window, and locators all passed. The final release runs settled in 2.2–2.3 seconds at 439 nodes. `webArea`, `primaryView`, `composerEditor`, `sendButton`, and `messageList` each had one match. |
| 2. `current` | Exit `0`. A separate read-only Accessibility snapshot matched the reported conversation to the client window and its one rendered selected sidebar row. |
| 3. Tree restoration | The follow-up `doctor` reported `enabled by this run`. The recovery marker count was zero after exit. |
| 4. `doctor` over SSH | Exit `10` with `accessibility_not_trusted`. macOS reported an unlocked console session for this SSH invocation. |
| 5. Concurrency | Two overlapping `current` commands both exited `0` in turn. A third with `--timeout 0.2` exited `14` with `busy`. The follow-up `doctor` enabled the tree again. |
| 6. Interrupt during settle | Sent `SIGINT` after the recovery marker appeared. `doctor` exited `130`, and zero recovery markers remained. The next `doctor` enabled the tree again and passed all eight checks. |
| 7. Locked screen | Skipped. Locking the live Mac was outside the authorized checks. |
| 8. Channel deep link and focus | Skipped. The disposable team and conversation were unavailable. |
| 9. DM link and sidebar press | Skipped. The disposable DM and user were unavailable. |
| 10. Nonexistent conversation | Skipped. This still requires opening a link against a disposable workspace. |
| 11. Minimized and hidden Slack | Skipped. Changing live Slack visibility was outside the authorized checks. |
