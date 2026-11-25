# channels

`slack-remote channels [--source sidebar|browser] [--team TEAM_ID]`

The default `sidebar` source lists the conversations in Slack’s sidebar. With no `--team`, it uses the workspace Slack is showing. With `--team`, it opens that workspace using a Slack link and checks the workspace ID before reading.

Each row includes the conversation ID, name, kind, selection, and draft flag. Use the conversation ID with another command’s `--channel` option. The kinds are `channel`, `dm`, `group_dm`, and `self_dm`.

The `browser` source lists the Channels tab of Slack’s directory and returns to the starting conversation. The browser’s rows have kind `channel` and do not expose sidebar selection or draft flags. If the native shortcut menu item leaves the view unchanged, the command opens the directory through **Add channels › Browse channels** in an English Slack client. The observed browser exposes no reliable end marker, so a full traversal can finish with a partial result.

`--max-items` defaults to 500 and accepts up to 5,000. `--max-pages` defaults to 100. The result includes `complete`, `stopReason`, and `pages`. A caller limit returns `limit` with exit status 0. When paging stalls or runs out of time, the command returns the items collected and exits with status 19. Use `--allow-partial` to return the same partial result as a success.
