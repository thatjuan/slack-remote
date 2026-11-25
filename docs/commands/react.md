# react

```sh
slack-remote react (--dest NAME | --team TEAM --channel ID) --ts TS --emoji SHORT_NAME
                   [--thread ROOT_TS] [--dry-run]
```

Use the message timestamp from [`read`](read.md) and an emoji name without the colons, such as `tada`. Use `--thread` with the parent message's timestamp when the target is inside a thread. The command can page back to find the target.

Success returns `ts`, `emoji`, `reacted: true`, and `alreadyReacted`. If the reaction is already yours, the command leaves it in place and returns `alreadyReacted: true`. If Slack exposes one of your reactions without identifying its emoji, the command returns `ui_drift` to avoid toggling it off.

`--dry-run` reports the planned checks without opening the picker. An unknown shortcode returns `unsafe_text`. If the picker press returns `reaction_unconfirmed`, check the message before retrying.

Slack can hide the target while the picker is open. The command verifies which message owns the menu and checks that the same client window, web area and conversation produced the picker. It searches by shortcode, requires one enabled exact match in the result grid, and recognizes row and column entries as duplicates only when they refer to the same Accessibility element. After pressing, it verifies the named, checked reaction on the original message.
