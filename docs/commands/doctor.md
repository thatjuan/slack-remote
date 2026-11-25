# doctor

```sh
slack-remote doctor [--timeout SECONDS] [--debug]
```

Checks the GUI session, screen lock, Accessibility permission, Slack process and visibility, tree readiness, selected client window, and expected locators. The result contains `checks`, each with `name`, `ok`, and optional `detail`. A failed check puts the results and the first error on stderr. See the exit status table in the [README](../../README.md).
