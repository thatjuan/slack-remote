# Typed call validation

Ran on main-mac on 2026-11-28 with the ad hoc signed SlackRemote.app 2.0.0 build. The Slack desktop process was absent during these checks.

| Check | Result |
| --- | --- |
| `doctor` | Exit 0. Verified both accounts and both sessions. GIF Monger took 139 ms and Altumo took 143 ms. |
| `whoami` | Exit 20 with `team_required` and both available workspace IDs. |
| `whoami --team T02R8SSJGCU` | Exit 0. Matched the GIF Monger account and returned its self-DM. |
| `whoami --team T04JKELQC` | Exit 0. Matched the Altumo account and returned its self-DM. |
| `accounts list` | Exit 0. Listed GIF Monger and Altumo in separate active accounts. |
| Ctrl-C during `doctor` | Sent SIGINT 80 ms after launch. The helper returned `interrupted` on stderr and the CLI exited 130. |
| `accounts add --wait` | Opened the sign-in window. After Juan signed in to a third workspace, the waiting CLI exited 0 with `opened: true` and the new workspace ID in `added`. |
| `accounts list` and `doctor` after sign-in | All three workspaces stayed active, and Slack verified each session. |

`swift build`, `swift test` and `git diff --check` passed. The Swift Testing runs reported 42 passing tests.
