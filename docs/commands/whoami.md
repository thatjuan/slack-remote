# whoami

```sh
slack-remote whoami [--team TEAM_ID] [--timeout SECONDS]
```

Reports the signed-in workspace and user after verifying the session with Slack. If there is exactly one active workspace, you can omit `--team`. When several are active, the command returns `team_required` with the available IDs in `error.details.teams`. You can also find the IDs with [accounts list](accounts.md).

The result includes `team`, `teamName`, `url`, `user`, `userName`, `selfDM` and `account`. The `account` value is the account ID from `accounts list`. If Slack cannot open the self-DM, `selfDM` is null and the envelope includes the `self_dm_unavailable` warning.
