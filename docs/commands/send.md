# send

```sh
slack-remote send (--dest NAME | --team TEAM --channel ID) --text TEXT
                  [--allow-broadcast] [--dry-run]
```

The command accepts the `--user`, `--route`, and `--interrupt` options described under [`open`](open.md). It writes into an empty composer or reuses an identical draft, then rechecks the destination, composer, and send button before pressing once. Success returns `team`, `conversation`, `route`, `method`, `sent: true`, and the rendered matching message timestamp `ts`.

`--dry-run` reports `dryRun: true`, `team`, `conversation`, `atDestination`, `account`, `composer`, and `plan`. It checks account identity using the sidebar and checks for a conflicting draft when the destination is already on screen.

`unsafe_text` covers blank text, more than 4,000 characters, control characters other than newline and tab, a leading `/` after whitespace, and standalone reaction shortcuts such as `+:tada:`. `--allow-broadcast` permits `@channel`, `@here`, and `@everyone`. A different draft or pending content returns `draft_conflict`. A configured write allowlist can return `write_not_allowed`, and a configured account must verify.

When a failure reports `draftLeft: true` before the press, rerun with the same text to reuse a matching draft or clear it with `draft clear --expect-text`. If the error is `send_unconfirmed`, Slack may have sent the message. Use `read` or check Slack before retrying.
