# Scripting slack-remote

Check the exit status before parsing stdout. On success the CLI writes one JSON document to stdout. A command failure writes one JSON document to stderr. Keep the streams separate. Help and argument errors are plain text. `--version` prints a version string.

```json
{
  "ok": true,
  "command": "dest list",
  "warnings": [],
  "result": { "destinations": {} }
}
```

```json
{
  "ok": false,
  "command": "whoami",
  "error": {
    "code": "team_required",
    "message": "Several Slack workspaces are available. Supply --team.",
    "details": { "teams": "T02R8SSJGCU,T04JKELQC" }
  }
}
```

On failure, `warnings`, `result` and `error.details` may be absent. For example, `doctor` can include its checks on failure. Branch on `error.code`. Use `message` and `details` for diagnostics.

## Exit statuses

| Status | Error codes and conditions |
| --- | --- |
| 0 | Success, help or version |
| 1 | `internal`, `not_implemented` |
| 10 | `helper_unavailable`, `helper_version_mismatch` |
| 11 | `session_unavailable`, `network_unavailable` |
| 13 | `destination_unreachable`, `unsupported_destination`, `message_not_found` |
| 14 | `rate_limited` |
| 15 | `unsafe_text`, `draft_conflict`, `write_not_allowed`, `file_rejected` |
| 17 | `send_unconfirmed`, `reaction_unconfirmed`, `upload_unconfirmed` |
| 18 | `timeout` |
| 19 | `partial_result` |
| 20 | `no_account`, `team_required`, `account_signed_out`, `sign_in_cancelled`, `account_mismatch`, `account_unverified`, `config_invalid` |
| 21 | `slack_api_error` |
| 64 | Invalid syntax or option values, reported by Swift Argument Parser |
| 130 | `interrupted` |

Slack commands run in SlackRemote.app and can run concurrently. When Slack rate-limits a request, the helper retries it if the wait fits within the command's deadline.

Set `SLACK_REMOTE_CONFIG` to use a private config file at a different path. The file must be owned by the current user and exclude group and other permissions. Relative paths resolve from the CLI's working directory.
