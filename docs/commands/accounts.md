# accounts

```sh
slack-remote accounts list
slack-remote accounts add [--wait] [--timeout SECONDS]
slack-remote accounts remove ACCOUNT_ID
```

`list` returns the accounts stored in SlackRemote.app. Each account has an `id`, a `state` of `active` or `signedOut`, and a `teams` array. Each team has an `id`, `name`, `url`, `user` and `userName`.

`add` opens a sign-in window and returns `{"opened": true}`. With `--wait`, it returns once the window records an account and includes the workspace IDs in `added`. The default timeout is 300 seconds. Closing the window before sign-in returns `sign_in_cancelled` with exit status 20.

`remove` removes the account and its browser profile from this Mac without asking for confirmation. Pass the account ID from `accounts list`. An unknown ID returns `no_account` with exit status 20.
