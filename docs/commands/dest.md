# dest

```sh
slack-remote dest add NAME --team TEAM --channel ID
slack-remote dest list
```

`add` creates or replaces a local alias for a workspace and conversation. Names use 1–32 lowercase letters, digits, underscores or hyphens. `ID` can be a channel, DM, or group conversation ID. Both subcommands return `destinations`, a map from names to objects containing `team` and `conversation`.

The commands edit or read the private config without opening Slack. Invalid JSON or permissions return `config_invalid`. An unused config lists an empty map.
