# slack-remote

`slack-remote` is a macOS command-line tool for reading and controlling the Slack desktop client. It uses Slack’s documented deep links and macOS Accessibility to navigate conversations, read rendered messages, search and send.

## Requirements

- macOS 14 or later on Apple silicon or Intel
- The Slack desktop app, running and visible in a signed-in, unlocked macOS session
- Accessibility access for the app launching the CLI, under **System Settings › Privacy & Security › Accessibility**
- Swift 6 or later to build from source

## Install

From a source checkout, run:

```sh
scripts/install.sh
export PATH="$HOME/.local/bin:$PATH"
slack-remote --version
```

Pass `--prefix DIR` to install to `DIR/bin`. Use `scripts/uninstall.sh` with the same prefix to remove the binary while keeping local configuration and support files. For a release archive, verify the companion checksum with `shasum -a 256 -c slack-remote-1.0.0-macos.zip.sha256`, then unzip and put the executable on your `PATH`. The archive contains an ad hoc signed universal binary.

## First run

Run `slack-remote doctor` from the app you plan to use for scripting and resolve any failed checks. In your Slack workspace, run `slack-remote whoami --save` to record the signed-in account. Open a conversation in Slack and run `slack-remote current` to get its team and conversation IDs. Save those IDs under a name you can pass to `--dest`:

```sh
slack-remote dest add notes --team "$TEAM_ID" --channel "$CONVERSATION_ID"
slack-remote read --dest notes
```

Set `restrictWritesToDestinations` to `true` in `~/.config/slack-remote/config.json` to restrict writes to configured destinations. Keep the file private with mode `0600`.

## Commands

| Command | Purpose |
| --- | --- |
| [`doctor`](docs/commands/doctor.md) | Check the local session and Slack prerequisites |
| [`current`](docs/commands/current.md) | Report the view Slack is displaying |
| [`whoami`](docs/commands/whoami.md) | Identify the signed-in account and optionally save it |
| [`dest`](docs/commands/dest.md) | Save or list named destinations |
| [`open`](docs/commands/open.md) | Open and verify a conversation |
| [`read`](docs/commands/read.md) | Read rendered messages, history or a thread |
| [`channels`](docs/commands/channels.md) | List sidebar or channel browser conversations |
| [`members`](docs/commands/members.md) | List members of a channel or group |
| [`people`](docs/commands/people.md) | List the workspace people directory |
| [`search`](docs/commands/search.md) | Search Slack and optionally jump to a message |
| [`draft`](docs/commands/draft.md) | Set or clear a draft after checking its content |
| [`send`](docs/commands/send.md) | Send text to a verified conversation |
| [`reply`](docs/commands/reply.md) | Send text in a verified thread |
| [`react`](docs/commands/react.md) | Add an emoji reaction to a verified message |
| [`upload`](docs/commands/upload.md) | Send one local file to a conversation or thread |
| [`inspect`](docs/commands/inspect.md) | Print the Accessibility structure for diagnosis |

See the [scripting reference](docs/scripting.md) for JSON, exit statuses and a shell example. The [release validation matrix](docs/validation/matrix.md) records tested workflows and open gaps.

## Limits

- The CLI sees what Slack renders. History scrolls through the client within the supplied bounds. Slack controls search ranking, results and excerpts. History reports an incomplete result when it cannot verify the start of the conversation. [History validation](docs/validation/v1-foundation.md)
- Opening a conversation or thread marks it viewed as it would in the desktop app. Search can add terms to Slack’s recent searches.
- The lock serializes commands against one Slack client. An assistive tool that also toggles Slack’s Accessibility mode can cause `tree_unavailable`.
- Enterprise Grid, multiple Slack windows and non-English Slack are unvalidated. Core view locators use structure and are expected to work in other languages. The upload item and the directory fallback through **Add channels › Browse channels** use English labels. [Upload validation](docs/validation/upload.md), [listing validation](docs/validation/listing.md)
- The channel browser and people directory may return partial results. Slack did not expose a reliable end marker for either list or an expected count for the people directory. [Listing validation](docs/validation/listing.md)
- The members command supports channel and group lists. A self-DM has no supported members view. [Listing validation](docs/validation/listing.md)
- Slack’s attachment preview can stay open during verified self-DM navigation and reads. Primary draft, send, and upload commands can use the configured self-DM composer when that exact preview stays passive. [Self-DM validation](docs/validation/write.md#self-dm-write-preflight)
- People and Channels search sources require workspace scope because Slack drops the conversation filter on those tabs. The DMs source does not support a channel scope. Search can filter a DM only for the saved self-DM, which Slack exposes as a verifiable quick filter. Jump requires a message result with a verifiable identity. [Search validation](docs/validation/search.md)
- The native file picker sometimes omits paths from its Accessibility rows. Upload can use Slack’s native Paste command after it verifies composer focus. [Upload validation](docs/validation/upload.md)
- Inline emoji whose shortcodes Slack omits are flagged as `emojiOmitted`. Reaction controls that do not expose a verifiable identity cause the command to stop. [Thread and reaction validation](docs/validation/threads-reactions.md)
