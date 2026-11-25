# reply

```sh
slack-remote reply (--dest NAME | --team TEAM --channel ID) --thread TS --text TEXT
                   [--also-send-to-channel] [--allow-broadcast] [--dry-run]
```

Use the parent message's timestamp from [`read`](read.md). The command opens or reuses its thread, verifies the conversation and parent, and uses the thread's composer. An existing draft must match the supplied text exactly after normalization.

`--also-send-to-channel` sets the thread's broadcast checkbox. By default the command verifies that it is off before sending. `--allow-broadcast` separately permits Slack's broadcast mentions in the reply text. The [`send`](send.md) text rules, account checks, and write allowlist also apply.

Success returns the usual `send` fields plus `thread`, the parent timestamp. `--dry-run` displays the plan and checks a matching thread's composer if it is already on screen. If the result is `send_unconfirmed`, check the thread before retrying.
