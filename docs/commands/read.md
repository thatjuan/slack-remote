# read

```sh
slack-remote read [--dest NAME | --team TEAM --channel ID] [--limit N]
slack-remote read (--dest NAME | --team TEAM --channel ID) --history
                  [--since TS] [--max-messages N] [--max-pages N] [--allow-partial]
```

With a destination, `read` accepts the same `--user`, `--route`, and `--interrupt` options as [`open`](open.md).

Rendered reads return the message list Slack has drawn, in order from oldest to newest. Without a destination the command reads the current view in place. By default it returns every rendered message. `--limit N` keeps the newest N, including an empty array for zero.

`--history` scrolls toward older messages and attempts to return to the newest message before exiting. It defaults to 200 messages and 50 pages, with an upper limit of 2,000 messages. `--since` accepts a Slack timestamp such as `1700000000.000100` and keeps messages strictly newer than it. Messages that arrive during paging can appear in the snapshot.

Both results contain `team`, `conversation`, `route`, `scope`, `complete`, `stopReason`, `pages`, `readAt`, `skippedItems`, and `messages`. History adds `scrollRestored` and, when messages are returned, `oldestTs` and `newestTs`. Rendered results always report `complete: false`, `stopReason: "limit"`, and `pages: 0`.

History exits successfully at the requested boundary or limit. A stall or deadline returns `partial_result` (19). Pass `--allow-partial` to return the available messages with `complete: false` and the corresponding stop reason. A rendered account mismatch returns `account_mismatch`. An existing modal or sheet returns `ui_blocked`.
