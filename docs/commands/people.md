# people

```sh
slack-remote people [--team T] [--include-bots] [--include-deleted]
                    [--limit N] [--allow-partial] [--timeout S]
```

List a Slack workspace's users. Include bots and Slackbot with `--include-bots` and deleted users with `--include-deleted`. A deleted bot requires both flags. Pass `--team` when multiple workspaces are signed in.

`--limit` defaults to 500 and accepts 1–5,000. The limit counts users who pass the filters. The result has the workspace ID `team`, a `people` array, and the [list fields](../scripting.md#list-results) `complete`, `stopReason`, and `pages`.

| Person field | Meaning |
| --- | --- |
| `user` | Slack user ID |
| `name` | Slack username or handle, when available |
| `realName` | Real name from the Slack user record, when available |
| `displayName` | Profile display name, when available |
| `isBot` | Whether the account is a bot, app user or Slackbot |
| `deleted` | Whether Slack reports the user as deleted |
