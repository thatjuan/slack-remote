# read

```sh
slack-remote read [--dest NAME | --team TEAM --channel ID] [--limit N]
slack-remote read (--dest NAME | --team TEAM --channel ID) --history
                  [--since TS] [--max-messages N] [--max-pages N] [--allow-partial]
slack-remote read (--dest NAME | --team TEAM --channel ID) --thread TS
                  [--limit N | --history] [--close-thread] [--dry-run]
```

With a destination, `read` accepts the same `--user`, `--route`, and `--interrupt` options as [`open`](open.md).

Rendered reads return the message list Slack has drawn, in order from oldest to newest. Without a destination the command reads the current view in place. By default it returns every rendered message. `--limit N` keeps the newest N, including an empty array for zero.

`--history` scrolls toward older messages and reserves time to return to the last message in Slack’s initial rendered list. It defaults to 200 messages and 50 pages, with an upper limit of 2,000 messages. `--since` accepts a Slack timestamp such as `1700000000.000100` and keeps messages strictly newer than it. Messages that arrive during paging can appear in the snapshot.

Both results contain `team`, `conversation`, `route`, `scope`, `complete`, `stopReason`, `pages`, `readAt`, `skippedItems`, and `messages`. History adds `scrollRestored` and, when messages are returned, `oldestTs` and `newestTs`. `scrollRestored: true` confirms the starting message is rendered again in the same conversation or thread. It makes no claim about the exact viewport position. Rendered conversation reads report `complete: false`, `stopReason: "limit"`, and `pages: 0`.

`--thread TS` uses the parent message's timestamp. The result adds `thread` and uses `scope: "rendered-thread"`. A rendered thread read reports one snapshot in `pages`. Combine it with `--history` to page the thread and use the history options above. The pane stays open unless you pass `--close-thread`. `--dry-run` reports the plan without opening a pane.

In message text, an emoji with a Slack shortcode appears as `:short_name:`. A message includes `emojiOmitted: true` if Slack exposes an emoji image without a shortcode.

History exits successfully at the requested boundary or limit. A stall or deadline returns `partial_result` (19). Pass `--allow-partial` to return the available messages with `complete: false` and the corresponding stop reason. A rendered account mismatch returns `account_mismatch`. An existing modal or sheet returns `ui_blocked`.
