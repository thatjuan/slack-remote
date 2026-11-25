# members

`slack-remote members --dest NAME`

`slack-remote members --team TEAM_ID --channel CONVERSATION_ID`

Lists users from the conversation’s Members tab and closes the details dialog afterwards. Each row includes a Slack user ID and the label shown in the dialog. Direct messages return `unsupported_destination`.

`--max-items` defaults to 500 and accepts up to 5,000. `--max-pages` defaults to 100. The result includes `complete`, `stopReason`, `pages`, and `expectedCount`. `expectedCount` is the first integer in the Members tab label or `null` if the tab has no count. A count mismatch reports a stall unless paging stopped at a caller limit.

A caller limit returns `limit` with exit status 0. When paging stalls or runs out of time, the command returns the items collected and exits with status 19. Use `--allow-partial` to return the same partial result as a success.
