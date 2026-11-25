# open

```sh
slack-remote open (--dest NAME | --team TEAM --channel ID)
                  [--user USER] [--route auto|sidebar] [--interrupt] [--dry-run]
```

Opens a channel, DM, or group conversation and verifies the workspace, conversation, and sidebar selection. Auto opens the documented Slack channel link for all conversation IDs. With a DM and `--user`, auto uses the Slack user link. Use `--route sidebar` to press the rendered conversation control. `--interrupt` allows navigation when Slack is frontmost and received input in the last 30 seconds.

The result contains `team`, `conversation`, `route`, and `focusRestored`. Routes are `already_there`, `deep_link_channel`, `deep_link_user`, or `sidebar_row`. `--dry-run` reports `team`, `conversation`, `atDestination`, `account`, `composer`, and `plan` with `dryRun: true`. When the requested conversation is off screen, `composer` is `unknown`.

A rendered account mismatch returns `account_mismatch`. A missing alias returns `unsupported_destination`, and a missing row for the explicit sidebar route returns `destination_unreachable`. A conversation or selection that differs from the request returns `destination_mismatch`.

Open accepts Slack’s attachment preview when the client URL, selected sidebar row, signed-in self-DM marker, and primary view all verify the self-DM. The preview stays open. Other blocking modals and sheets return `ui_blocked`. Writes still require an unblocked view.
