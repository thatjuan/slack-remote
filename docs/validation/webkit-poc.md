# WebKit PoC validation

## Decision record

- Transport
- API endpoint
- Idle document
- Sign-in methods
- Go or no-go

## `localConfig_v2` fields

Field names to confirm during live validation. The token is redacted.

```json
{
  "teams": {
    "T0123ABCD": {
      "id": "T0123ABCD",
      "name": "Acme",
      "domain": "acme",
      "url": "https://acme.slack.com/",
      "token": "[redacted]",
      "user_id": "U0123ABCD",
      "enterprise_id": null
    }
  }
}
```

## Live test matrix

| # | Check | Pass when | Outcome |
| --- | --- | --- | --- |
| 1 | Sign in with email and confirmation code | Window closes; `webkit-poc accounts` lists the team | pending |
| 2 | Sign in with Google | Same. If Google shows `disallowed_useragent` or “This browser or app may not be secure”, record the exact screen and URL | pending |
| 3 | Sign in through SAML or Okta, if any workspace uses it | Same, or recorded as not available | pending |
| 4 | Add a second workspace in the same window through Slack’s own “sign in to another workspace” flow | Both teams appear under one store | pending |
| 5 | Second account in a separate store | Both work; tokens differ; signing out of one leaves the other signed in | pending |
| 6 | `auth.test` with each transport, window closed | `ok: true`; `user_id` matches the team record | pending |
| 7 | `conversations.history` (`channel`, `limit=5`) on a known channel and `conversations.replies` on a known thread | Messages match what Slack shows | pending |
| 8 | Quit and relaunch SlackRemote, repeat 6–7 without signing in | Pass | pending |
| 9 | Idle 30 minutes with no window open, then 20 consecutive `auth.test` calls per transport | Record p50 and max `elapsedMs`. Pass when p50 < 500 ms | pending |
| 10 | Repeat 9 with the screen locked, and from an `ssh user@main-mac` shell | Record | pending |
| 11 | WebContent memory (`footprint` or Activity Monitor) for the idle document vs the full client | Record both | pending |
| 12 | Log out of macOS and back in (or reboot), repeat 6 | Pass | pending |
| 13 | 60 rapid `conversations.history` calls | Record whether Slack returns HTTP 429 or `error: "ratelimited"` and the `Retry-After` value | pending |
| 14 | In the sign-in window’s client, sign out of one workspace, then call `auth.test` | Record the error code (expected `invalid_auth`) | pending |
| 15 | `loadClient()` then `localConfig()` after the client has run for a minute | Record whether the token changes | pending |
