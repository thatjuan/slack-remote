# upload

Share a local file in a Slack conversation or thread.

```sh
slack-remote upload --dest notes --file ./report.pdf --text 'Latest report'
slack-remote upload --dest notes --file ./report.pdf --thread 1700000400.000300 --timeout 60
```

Supply `--dest NAME` or both `--team T` and `--channel C`. Use the parent message timestamp for `--thread`. The optional caption follows the [message text rules](send.md), with broadcast mentions blocked.

The source must be a nonempty regular file. The default size limit is 50,000,000 bytes. Set `--max-size` to a value from 1 to 1,000,000,000 bytes to change the limit. Names that begin with a dot or contain slashes, a colon, a backslash or control characters are rejected. `--dry-run` checks the file and verifies the destination without uploading. Use `--timeout S` to change the 15-second default.

```json
{
  "team": "T02R8SSJGCU",
  "conversation": "C0CMFR1S2AZ",
  "thread": null,
  "fileId": "F012AB3CDE4",
  "fileName": "report.pdf",
  "size": 24576,
  "ts": "1700000400.000300"
}
```

Slack may take time to report the share message's timestamp. If it is still unavailable after up to five seconds of polling, the upload succeeds with `ts: null` and the warning `share_pending`. If the upload returns `upload_unconfirmed`, check the destination before retrying.
