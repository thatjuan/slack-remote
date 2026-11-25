# people

`slack-remote people [--team TEAM_ID]`

Lists users from the People tab of Slack’s directory and returns to the starting conversation. Each row includes a Slack user ID and the card’s display label. With no `--team`, the command uses the workspace Slack is showing. With `--team`, it opens that workspace using a Slack link and checks the workspace ID.

If **Go › People & User Groups** leaves the view unchanged, the command opens the directory through **Add channels › Browse channels** in an English Slack client and selects the People tab.

Slack can reopen a scoped search pane during the return to the starting conversation. The command closes it when the window, conversation and account checks identify it as reopened by that return. Panes already open when the directory command starts stay open. If clean return cannot be verified, the command can report `overlay_left_open`.

`--max-items` defaults to 500 and accepts up to 5,000. `--max-pages` defaults to 100. The result includes `complete`, `stopReason`, `pages`, and `expectedCount`. The observed grid has no reliable count or end marker, so `expectedCount` is `null` and a full traversal can finish with a partial result.

A caller limit returns `limit` with exit status 0. When paging stalls or runs out of time, the command returns the items collected and exits with status 19. Use `--allow-partial` to return the same partial result as a success.
