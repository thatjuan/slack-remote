# doctor

```sh
slack-remote doctor [--timeout SECONDS]
```

Checks SlackRemote.app and the sessions stored in it. The default timeout is 15 seconds. The result contains a `checks` array with `name`, `ok`, and `detail` for each check, in this order.

| Check | Detail |
| --- | --- |
| `helper` | The running helper's version. |
| `accounts` | The number of active accounts and workspaces, or how to add an account. |
| `session:<TEAM>` | One check per recorded workspace. Reports its name, user and elapsed time when `auth.test` verifies the user. Otherwise it reports the error code. |

If a check fails, the command writes its result and the first error to stderr and exits with that error's status. [Exit statuses](../scripting.md#exit-statuses)
