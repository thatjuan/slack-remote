# read

```sh
slack-remote read (--dest NAME | --team T --channel C) [--thread TS]
                  [--since TS] [--until TS] [--limit N] [--allow-partial] [--timeout S]
```

Read conversation history or a thread through Slack's Web API. Reading preserves the conversation's unread state.

Conversation history returns up to the newest `N` messages, oldest first. A thread returns up to the earliest `N` messages, parent first. Give `--thread` the parent's timestamp. A reply timestamp returns `message_not_found`. Use Slack timestamps such as `1700000000.000100`. The `--since` and `--until` bounds are exclusive.

`--limit` defaults to 50 and accepts 1–2,000. See [List results](../scripting.md#list-results) for deadlines and partial output.

| Result field | Meaning |
| --- | --- |
| `team`, `conversation` | Slack workspace and conversation IDs |
| `thread` | Requested parent timestamp or `null` |
| `complete`, `stopReason`, `pages` | Paging outcome. `boundary` means Slack exhausted the range supplied with `--since`. |
| `oldestTs`, `newestTs` | First and last returned timestamps, or `null` for an empty list |
| `readAt` | Time of the read in ISO 8601 UTC |
| `messages` | Messages in chronological order |

| Message field | Meaning |
| --- | --- |
| `ts` | Slack message timestamp, preserved as a string |
| `user`, `userName` | Author's ID and resolved name. Either may be `null`. Bot posts can supply their own name. |
| `botId`, `subtype` | Slack bot ID and subtype, or `null` |
| `text` | Stored Slack mrkdwn, including shortcode emoji and markup for links and mentions |
| `threadTs`, `replyCount` | Parent timestamp for thread messages and reply count for parents. Otherwise the fields are `null`. |
| `edited` | Whether Slack returned edit metadata |
| `files` | Attachments with `id`, `name`, `title`, `mimetype`, `size` in bytes, and `permalink`. Slack may omit metadata other than the ID. |
| `reactions` | Each has a Slack shortcode `name`, a total `count`, and `reacted`, which indicates whether Slack included the signed-in user among its reactors. |
