<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo-slack-remote-dark.svg">
    <img alt="slack-remote" src="brand/logo-slack-remote-outlined.svg" width="420">
  </picture>
</p>

`slack-remote` is a macOS command-line tool for reading and controlling the Slack desktop client. It uses Slack’s documented deep links and macOS Accessibility to navigate conversations, read rendered messages, search and send.

## Requirements

- The binary targets macOS 14 or later on Apple silicon and Intel.
- Sign in to the Slack desktop app and keep it open and visible in an unlocked macOS GUI session.
- In **System Settings › Privacy & Security › Accessibility**, grant access to Terminal or whichever app launches `slack-remote`.

## Install

### Install from the ZIP

Save `slack-remote-1.0.0-macos.zip` and `slack-remote-1.0.0-macos.zip.sha256` from the private item to the same folder. The ZIP contains the ad hoc signed universal binary, this README, and the command docs.

In Terminal, change to that folder and run the block below. If the SHA-256 check fails, the install stops.

```sh
(
  shasum -a 256 -c slack-remote-1.0.0-macos.zip.sha256 &&
  unpack_dir=$(mktemp -d) &&
  trap 'rm -rf "$unpack_dir"' EXIT &&
  unzip slack-remote-1.0.0-macos.zip slack-remote -d "$unpack_dir" &&
  mkdir -p "$HOME/.local/bin" &&
  install -m 755 "$unpack_dir/slack-remote" "$HOME/.local/bin/slack-remote"
) &&
export PATH="$HOME/.local/bin:$PATH" &&
slack-remote --version
```

Add the `export PATH` line to `~/.zshrc` if you want `slack-remote` on your `PATH` in future zsh sessions.

### Build from source

Use an Xcode toolchain with Swift 6 or later. Clone the `slack-remote-v0.1` branch of the private repository and run the installer.

```sh
git clone --branch slack-remote-v0.1 git@github.com:thatjuan/slack-remote.git &&
cd slack-remote &&
scripts/install.sh
```

After PR #5 merges, omit `--branch slack-remote-v0.1` from the clone command.

The installer puts `slack-remote` in `~/.local/bin`. Run the `export PATH` and `slack-remote --version` lines above. Pass `--prefix DIR` to install into `DIR/bin`, then add that directory to `PATH`. To remove the binary, run `scripts/uninstall.sh` with the same prefix option.

## First run

Run `slack-remote doctor` from the app that will launch the CLI and resolve any failed checks. In each workspace you plan to write to, run `slack-remote whoami --save` to record the active account in your local config.

To set up a named destination, open the conversation in Slack and run `slack-remote current`. Put the returned `team` and `conversation` IDs in `TEAM_ID` and `CONVERSATION_ID`, then save and use the alias.

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
- Slack’s attachment preview can stay open during verified self-DM navigation and reads. Primary draft, send, and upload commands can use the configured self-DM composer when that exact preview stays passive. [Self-DM validation](docs/validation/write.md#live-recovery-under-the-passive-preview)
- People and Channels search sources require workspace scope because Slack drops the conversation filter on those tabs. The DMs source does not support a channel scope. Search can filter a DM only for the saved self-DM, which Slack exposes as a verifiable quick filter. Jump requires a message result with a verifiable identity. [Search validation](docs/validation/search.md)
- The native file picker sometimes omits paths from its Accessibility rows. Upload can use Slack’s native Paste command after it verifies composer focus. [Upload validation](docs/validation/upload.md)
- Inline emoji whose shortcodes Slack omits are flagged as `emojiOmitted`. Reaction controls that do not expose a verifiable identity cause the command to stop. [Thread and reaction validation](docs/validation/threads-reactions.md)
