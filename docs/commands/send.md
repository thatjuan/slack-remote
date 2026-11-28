# send

Post text to a Slack channel or direct message.

```sh
slack-remote send --dest notes --text 'The build is ready.'
slack-remote send --team T02R8SSJGCU --channel C0CMFR1S2AZ --text 'The build is ready.' --dry-run
```

Supply `--dest NAME` or both `--team T` and `--channel C`. `--dry-run` checks the destination and account and returns [the planned write](../scripting.md#command-effects). Use `--timeout S` to change the 15-second default.

Text can contain up to 4,000 characters. Blank text, control characters other than tabs and newlines, slash commands, reaction shortcuts such as `+:tada:` and invalid emoji names give `unsafe_text`. Broadcast mentions such as `@here` or `<!here>` require `--allow-broadcast`.

Slack returns the timestamp of the posted message.

```json
{ "team": "T02R8SSJGCU", "conversation": "C0CMFR1S2AZ", "sent": true, "ts": "1700000400.000300" }
```

If Slack does not respond to the post request, the command returns `send_unconfirmed`. Check the conversation before retrying.
