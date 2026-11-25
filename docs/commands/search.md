# slack-remote search

```sh
slack-remote search --query TEXT
    [--type TYPE] [--in NAME | --in-team TEAM --in-channel CHANNEL]
    [--from-me] [--has-link] [--threads-only] [--team TEAM]
    [--max-results N] [--max-pages P] [--allow-partial] [--open INDEX]
```

Search runs in the signed-in Slack client. Slack interprets any search modifiers in `TEXT`. The command checks the query field before submitting and verifies the conversation filter by ID. `--in` uses a configured destination name. Filtering a DM currently requires the configured account's self-DM.

Without a conversation filter, `--team` uses the current conversation in that workspace or the account's configured self-DM to switch workspaces. Use `--interrupt` to allow search while Slack has recent user input.

The default type is `messages`. Use `--in NAME` or `--in-team TEAM --in-channel CHANNEL` to search a specific channel or self-DM. Slack can provide additional types through its Sources menu. Look in `availableTypes` for the current choices. An empty channel search may expose only messages.

People and Channels are workspace-scoped sources. Run them without `--in`, the explicit conversation flags, or a Slack `in:` modifier. Add `--team TEAM` if you need to switch workspaces.

```sh
slack-remote search --type people --query "Ada"
slack-remote search --type channels --query "planning"
```

Slack discards the conversation filter for these sources. A conversation flag returns `unsupported_destination` before the CLI opens search.

Results follow Slack's order at the time of the search. Slack chooses the ranking and may truncate the rendered message excerpts. The CLI keeps result types separate. `complete: true` means the CLI reached the end of the results Slack listed for the selected type. The workspace may hold other matches.

The defaults are 50 results and 20 pages. `--max-results` accepts 1–1,000. Each result set reports `complete`, `stopReason`, and `pages`. An explicit bound reports `limit`. A stall or deadline returns `partial_result` (19), or the available results if you pass `--allow-partial`.

Search returns to the starting conversation after reading the results. `--open INDEX` selects a zero-based message result and leaves Slack on the verified message destination. The result includes `opened.inThread` when the message appears in the thread pane. Results with `idSource: "none"` have null identifiers and cannot be opened. The `sort` field is null when Slack exposes no selected sort.

Ctrl-C exits with status 130 after one bounded cleanup attempt. If the command cannot close its popup or restore the starting conversation, it reports the cleanup error on stderr.
