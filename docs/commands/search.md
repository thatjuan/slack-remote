# slack-remote search

```sh
slack-remote search --query TEXT
    [--type TYPE] [--in NAME | --in-team TEAM --in-channel CHANNEL]
    [--from-me] [--has-link] [--threads-only] [--team TEAM]
    [--max-results N] [--max-pages P] [--allow-partial] [--open INDEX]
```

Search runs in the signed-in Slack client. Slack interprets any search modifiers in `TEXT`. The command checks the query field before submitting and verifies the conversation filter by ID. `--in` uses a configured destination name. Filtering a DM currently requires the configured account's self-DM.

The default type is `messages`. Slack can provide additional types through its Sources menu. Look in `availableTypes` for the choices on the current results view. An unsupported type returns `unsupported_destination` with those choices in the error details. An empty channel search may expose only messages. People and Channels require a search without the conversation flag on the tested client.

Results follow Slack's order at the time of the search. Slack chooses the ranking and may truncate the rendered message excerpts. The CLI keeps result types separate. `complete: true` means the CLI reached the end of the results Slack listed for the selected type. The workspace may hold other matches.

The defaults are 50 results and 20 pages. `--max-results` accepts 1–1,000. Each result set reports `complete`, `stopReason`, and `pages`. An explicit bound reports `limit`. A stall or deadline returns `partial_result` (19), or the available results if you pass `--allow-partial`.

Search returns to the starting conversation after reading the results. `--open INDEX` selects a zero-based message result and leaves Slack on the verified message destination. The result includes `opened.inThread` when the message appears in the thread pane. Results with `idSource: "none"` have null identifiers and cannot be opened.
