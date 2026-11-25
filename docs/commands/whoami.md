# whoami

```sh
slack-remote whoami [--save]
```

Identifies the signed-in account in Slack's current workspace. The result contains `team`, `user`, and `selfDM`, which is null when the self-DM row is outside the rendered sidebar. The command opens Slack's search popup to read the signed-in user's quick filter and closes it afterward. `--save` adds or replaces the local account entry for the workspace.

If Slack omits the search backdrop, the command can rebuild its own Accessibility session once before looking for the owned backdrop again.

An existing modal or sheet returns `ui_blocked`. If the search popup cannot close and reveal the primary view, the command returns `overlay_left_open`. Unreadable or invalid settings return `config_invalid` when saving.
