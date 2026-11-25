# current

```sh
slack-remote current [--timeout SECONDS] [--debug]
```

Returns Slack's current view. A conversation result has `view: "conversation"`, `team`, `conversation`, `kind`, and `trailing` URL segments. Another client view has `view: "other"`, `team`, and `path`.

`ambiguous_window` means Slack has multiple client windows and no unique main window. An open modal or sheet returns `ui_blocked`.
