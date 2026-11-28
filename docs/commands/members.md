# members

```sh
slack-remote members (--dest NAME | --team T --channel C) [--limit N] [--allow-partial] [--timeout S]
```

List the users in a Slack channel, DM or group DM. `--limit` defaults to 500 and accepts 1–5,000.

The result includes the Slack workspace ID `team`, conversation ID `conversation`, and a `members` array. Each member has `user`, a Slack user ID, and `name`, the resolved display label when available. See [List results](../scripting.md#list-results) for `complete`, `stopReason`, `pages`, and deadline handling.
