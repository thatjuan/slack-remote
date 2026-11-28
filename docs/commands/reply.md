# reply

Post text in a Slack thread. Pass the parent message's timestamp to `--thread`.

```sh
slack-remote reply --dest notes --thread 1700000400.000300 --text 'Ready for review.'
slack-remote reply --dest notes --thread 1700000400.000300 --text 'Ready for review.' --also-send-to-channel
```

Supply `--dest NAME` or both `--team T` and `--channel C`. Use `--also-send-to-channel` to share the reply in the main conversation as well. Replies follow the same [text rules](send.md) and `--allow-broadcast` behavior as `send`. `--dry-run` verifies the destination and thread without posting. Use `--timeout S` to change the 15-second default.

Slack returns the reply timestamp in `ts` and the parent timestamp in `thread`. An unknown timestamp or a timestamp belonging to a reply gives `message_not_found`. If Slack does not respond to the post request, the command returns `send_unconfirmed`. Check the thread before retrying.
