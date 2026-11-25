# doctor

```sh
slack-remote doctor [--grant] [--timeout SECONDS] [--debug]
```

Checks the GUI session, screen lock, Accessibility permission, Slack process and visibility, tree readiness, selected client window, and expected locators. The result contains `checks`, each with `name`, `ok`, and optional `detail`. A failed check puts the results and the first error on stderr. See [Exit statuses](../scripting.md#exit-statuses).

The first check, `helper`, always reports `ok: true`. Its detail is `via SlackRemote.app <version>` when the helper runs the command, or `not used: <reason>` when the CLI runs it directly. The reasons are `disabled`, `not_installed`, and `not_running`.

Run `slack-remote doctor --grant` to grant Accessibility to SlackRemote.app when it runs the command. When the CLI runs directly, run it from the terminal, editor or agent app that will launch the CLI. If Accessibility access is missing and the GUI session is unlocked, it shows the macOS permission prompt, adds the host app to the Accessibility list, and opens that pane in System Settings (named Device Control and Data Access on macOS 27). Turn on the host app's switch. Doctor waits up to 120 seconds, checking every half second, then continues with its Slack checks or exits with `accessibility_not_trusted` (status 10). Press Ctrl-C to stop waiting (status 130). The Slack checks still get the full `--timeout` budget after this wait.

If access is already granted, `--grant` continues without showing a prompt or opening Settings. Other commands and `doctor` without `--grant` never request permission or open Settings. A successful `accessibility_trusted` check includes the detected host app name in `detail` when known.

If the switch is already on but the check still fails, quit and reopen the host app, then run doctor again. Some terminals cache a denial until they relaunch.
