# draft

```sh
slack-remote draft set (--dest NAME | --team TEAM --channel ID) --text TEXT [--dry-run]
slack-remote draft clear (--dest NAME | --team TEAM --channel ID) --expect-text TEXT [--dry-run]
```

Both subcommands accept the `--user`, `--route`, and `--interrupt` options described under [`open`](open.md). Draft comparison uses Unicode NFC, converts CRLF to LF, and ignores one trailing newline.

`set` writes text to an empty composer or reuses an identical draft. The result contains `team`, `conversation`, `route`, `method`, and `length`. `clear` clears a draft that matches `--expect-text`. If the composer is empty, the command succeeds with `cleared: false`. Its result contains `team`, `conversation`, `route`, and `cleared`.

A different draft or pending content returns `draft_conflict`. Text must meet the [`send`](send.md) content rules, including the ban on broadcast mentions. The account and write-restriction checks also apply. If a write fails after mutation, `draftLeft` is reported when the composer can be verified again.

`--dry-run` reports the planned operation with `dryRun: true`, `team`, `conversation`, `atDestination`, `account`, `composer`, and `plan`.
