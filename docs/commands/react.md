# react

Add an emoji reaction to a Slack message. For a threaded reply, use the reply's timestamp in `--ts`.

```sh
slack-remote react --dest notes --ts 1700000400.000300 --emoji tada
```

Supply `--dest NAME` or both `--team T` and `--channel C`. Give the emoji name without colons. An invalid name gives `unsafe_text` with reason `invalid_emoji_name`. A missing message gives `message_not_found`.

A successful result contains `team`, `conversation`, `ts`, `emoji`, `reacted: true` and `alreadyReacted`. If you already added this reaction, `alreadyReacted` is `true`. If Slack does not respond to the reaction request, the command returns `reaction_unconfirmed`.

`--dry-run` verifies the conversation and shows the planned reaction. Use `--timeout S` to change the 15-second default.
