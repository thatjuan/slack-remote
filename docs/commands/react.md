# react

```sh
slack-remote react (--dest NAME | --team TEAM --channel ID) --ts TS --emoji SHORT_NAME
                   [--thread ROOT_TS] [--dry-run]
```

Use the message timestamp from [`read`](read.md) and an emoji name without the colons, such as `tada`. Use `--thread` with the parent message's timestamp when the target is inside a thread. The command can page back to find the target.

Success returns `ts`, `emoji`, `reacted: true`, and `alreadyReacted`. If the reaction is already yours, the command leaves it in place and returns `alreadyReacted: true`. If Slack exposes one of your reactions without identifying its emoji, the command returns `ui_drift` to avoid toggling it off.

`--dry-run` reports the planned checks without opening the picker. An unknown shortcode returns `unsafe_text`. If the picker press returns `reaction_unconfirmed`, check the message before retrying.

Slack 4.53.292 can hide the target message while the picker is open and expose several cells with the same ID. The command closes the picker and stops before pressing when it cannot verify one target and one exact cell.
