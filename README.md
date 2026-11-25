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
- SlackRemote.app holds the Accessibility permission. Grant it once with `slack-remote doctor --grant`. Your terminal needs no permission when you use the helper.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/thatjuan/slack-remote/main/scripts/get.sh | sh
```

The script downloads the latest release, checks its SHA-256 and code signature, and installs the universal CLI into `~/.local/bin`. It puts SlackRemote.app in `~/Applications` and launches it. SlackRemote is a menu bar app with no Dock icon. It starts at login by default. The release uses a notarized Developer ID signature so the Accessibility grant survives upgrades.

Run the same command to upgrade. Pipe it to `sh -s -- --prefix DIR` to put the CLI in `DIR/bin`. If the bin directory is missing from your `PATH`, the script prints the line to add to `~/.zshrc`.

To install by hand, download `slack-remote-<version>-macos.zip` and its `.sha256` file, check the zip with `shasum -a 256 -c`, then extract it. Copy `slack-remote` onto your `PATH`, move SlackRemote.app into `~/Applications`, and open it. [Latest release](https://github.com/thatjuan/slack-remote/releases/latest)

To uninstall, run `scripts/uninstall.sh` from a source checkout. Pass the same `--prefix DIR` if you used one during install. To remove the files by hand, turn off Open at Login in the SlackRemote menu, quit the app, and delete it and the CLI.

### Build from source

Use an Xcode toolchain with Swift 6 or later.

```sh
git clone https://github.com/thatjuan/slack-remote.git &&
cd slack-remote &&
scripts/install.sh
```

The installer builds and starts SlackRemote.app in `~/Applications` and installs the CLI into `~/.local/bin`. Pass `--prefix DIR` to put the CLI in `DIR/bin`. By default, the installer signs the app ad hoc and macOS asks for Accessibility access again after each rebuild.

#### Sign your build

1. Open **Keychain Access › Certificate Assistant › Create a Certificate…**. Name it `slack-remote local`, set **Identity Type** to **Self Signed Root** and **Certificate Type** to **Code Signing**, then create the certificate.
2. Run `security find-identity -v -p codesigning` and check that the certificate is listed.
3. Run `scripts/install.sh --sign "slack-remote local"`. If `codesign` asks for keychain access the first time, choose **Always Allow**.
4. Run `slack-remote doctor --grant` once. Rebuilds signed with the same certificate keep the grant.

## First run

Run `slack-remote doctor --grant`, turn on the switch for SlackRemote when Settings opens, and resolve any failed checks. You can also enable SlackRemote manually in **System Settings › Privacy & Security › Accessibility** (**Device Control and Data Access** on macOS 27). In each workspace you plan to write to, run `slack-remote whoami --save` to record the active account in your local config.

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
