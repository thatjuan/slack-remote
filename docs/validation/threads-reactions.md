# Thread, reaction and emoji validation

The probes ran on main-mac against Slack 4.53.292 with the private write-restricted config. Each write used the project's lock and the verified signed-in account. The channel tests created two synthetic roots and used only those roots for thread and picker actions.

| Observation | Result |
| --- | --- |
| Thread rows | Both rendered threads returned the parent first, followed by the reply. The thread item IDs contained the verified conversation and root, and the pane contained one broadcast control. |
| Composer shortcode | A direct `AXValue` write returned the literal shortcode. A later write returned the same synthetic prefix with the shortcode missing, even though Send was enabled. The editor exposed no inline emoji structure to recover it. Both probes cleared only their own synthetic drafts. |
| Emoji in rendered text | Slack put `c-emoji` on an `AXGroup` inside the rich text section. Its only child was an `AXImage` with a title and description in the form `<short_name> emoji`. The image itself had no DOM classes. The reader recognizes this structure and emits a shortcode. The composer read-back required no Unicode-to-shortcode mapping. |
| Existing reaction label | Unverified. The synthetic reaction could not be added with a uniquely verified target. |
| Picker search | Setting the search field's `AXValue` changed the rendered grid. Four cells initially shared the exact ID. Two shared it after search, and other rendered IDs did not contain the search string. The client URL continued to match the channel. The primary view and target message disappeared from the tree, and the retained Accessibility elements could no longer return their current structure or identity. |

| Live check | Result |
| --- | --- |
| Reply dry run | Returned the plan without opening a popup or changing the destination. |
| Reply to a root with no replies | Confirmed exactly one reply under the requested parent. A primary read confirmed the reply was absent from the channel list. |
| Read the thread | Returned `scope: "rendered-thread"`, with the exact parent first and the reply after it. |
| Reply with a different thread open | Switched to the other synthetic root and confirmed exactly one reply under it. A read with `--close-thread` closed the verified pane. |
| Add and repeat a reaction | The picker rendered four cells with the same exact ID. The command returned `ui_drift` and closed the picker before pressing a cell. There was no reaction to repeat. |
| Unknown emoji | Returned `unsafe_text` with reason `unknown emoji`, then closed the picker. |
| Shortcode send and read in the channel | The first send returned `send_unconfirmed`. A later read found exactly one synthetic post and returned the original shortcode after the reader learned Slack's inline image structure. A separate send with fresh text stopped at `write_unverified` before the press because the editor omitted the shortcode. The generated draft was cleared by exact read-back. A live `sent: true` receipt for shortcode text remains unverified. |
| Self-DM | Opening the verified destination brought up an interactive popover. The CLI then blocked further commands, and the shortcode send was skipped. The existing draft was left untouched. A locked stock-client deep link returned Slack to the starting channel and verification found no blocking popup or sheet. |

Each channel check finished at the verified destination with no blocking popup or sheet. The release build, all 103 fixture tests, CLI help and invalid-emoji argument checks, and `git diff --check` passed.
