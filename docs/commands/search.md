# search

```sh
slack-remote search --query TEXT [--type messages|files] [--team T]
                    [--in NAME | --in-channel C] [--from-me] [--has-link] [--threads-only]
                    [--sort score|timestamp] [--limit N] [--allow-partial] [--timeout S]
```

Search messages or files with Slack's Web API. Messages and score order are the defaults. Use `--sort timestamp` for newest first. `--limit` defaults to 50 and accepts 1–1,000.

`--in NAME` selects a configured destination and its workspace. `--in-channel C` selects a conversation ID in the selected workspace. Without a destination supplying the team, pass `--team` when multiple workspaces are signed in.

The command appends filters to the query in this order.

| Flag | Modifier |
| --- | --- |
| `--in`, `--in-channel` | `in:#channel-name` for a channel or `in:@username` for a DM. Group DMs return `unsupported_destination`. |
| `--from-me` | `from:<@USER_ID>` for the signed-in user |
| `--has-link` | `has:link` |
| `--threads-only` | `is:thread` |

GIF Monger live checks confirmed all four modifiers, including `in:@username` for the self-DM. See [read validation](../validation/v2-read.md#search-modifiers).

Search checks each match against the requested conversation and author. When it drops matches, the envelope includes a `filtered_<n>` warning with the number dropped. For files the conversation check uses Slack's share metadata.

| Result field | Meaning |
| --- | --- |
| `team`, `type` | Workspace ID and `messages` or `files` |
| `query` | Search text sent to Slack, including modifiers |
| `total` | Match count reported by Slack before local filtering |
| `complete`, `stopReason`, `pages` | [List results](../scripting.md#list-results). Search uses numbered pages with a fixed page size to preserve page offsets. |
| `results` | Matches in Slack's order |

A message match contains `ts`, `conversation` (ID), `conversationName`, `user` (author ID), `userName`, `text` (Slack mrkdwn), and `permalink`.

A file match contains `id`, `name`, `title`, `mimetype`, `size` in bytes, `user` (owner ID), `userName`, `created` in Unix seconds, and `permalink`. Optional fields are omitted when Slack supplies no value or a name has yet to be resolved.
