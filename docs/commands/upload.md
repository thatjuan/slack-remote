# Upload a file

```sh
slack-remote upload --dest notes --file /path/to/report.txt --dry-run
slack-remote upload --dest self --file /path/to/report.txt
slack-remote upload --dest notes --file /path/to/report.txt --text 'Report for review'
slack-remote upload --dest notes --thread 1700000000.000400 --file /path/to/report.txt
```

Supply a configured destination with `--dest` or use `--team` and `--channel` together. To share a thread upload with the conversation as well, add `--also-send-to-channel`. Captions follow the same text rules as [send](send.md).

The file must be readable, nonempty and regular after resolving symlinks. Its name must be visible and contain no path separators or control characters. The default limit is 50,000,000 bytes. Set `--max-size` up to 1,000,000,000 bytes. `--dry-run` reports the file name, size and plan without staging the file or changing Slack.

The destination composer must be empty. The command uses a private staging copy in Downloads and cleans it up when the operation ends. When you run through SlackRemote.app, the CLI opens the source file and hands it to the helper. macOS may ask once for SlackRemote to access Downloads for staging. The command selects the file by its exact URL when the native panel exposes that URL. If the panel cannot expose a selectable path, the command cancels it and uses Slack's native Paste action with the staged file URL. It restores the clipboard if it still owns it.

A successful response includes the attachment method (`file_panel` or `file_paste`) and the message timestamp. A primary upload in the configured self-DM uses `file_paste` when the verified passive attachment preview is visible. If the command returns `upload_unconfirmed`, check the conversation or thread before retrying. For pre-send failures, `pendingFileLeft` and `draftLeft` report what may still be in the composer.
