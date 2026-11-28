# channels

```sh
slack-remote channels [--team T] [--source member|all] [--include-archived]
                      [--limit N] [--allow-partial] [--timeout S]
```

List conversations in a Slack workspace. The default source, `member`, includes channel memberships, DMs, group DMs and the self-DM. `--source all` lists the public channel directory. Pass `--include-archived` to include archived channels. Pass `--team` when multiple workspaces are signed in.

`--limit` defaults to 500 and accepts 1–5,000. The result has the workspace ID `team`, selected `source`, a `channels` array, and the [list fields](../scripting.md#list-results) `complete`, `stopReason`, and `pages`.

| Channel field | Meaning |
| --- | --- |
| `id` | Conversation ID for use with `--channel` |
| `name` | Slack conversation name, the other person's display label in a DM, or the account name in the self-DM. Omitted when unavailable. |
| `kind` | `channel`, `private_channel`, `dm`, `group_dm`, or `self_dm` |
| `archived` | Whether Slack reports the conversation as archived |
| `user` | The other person's Slack user ID, present for `dm` rows when available |
