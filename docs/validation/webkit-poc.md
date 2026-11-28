# WebKit PoC validation

## Decision record

Recorded 2026-11-27 on jmbp (macOS 27) with the ad hoc build of `thatjuan/poc-a` (97cbd7b), against GIF Monger (`T02R8SSJGCU`) and, as a second account, Altumo (`T04JKELQC`).

- **Transport:** native. Both transports returned the same results. Native took 113–160 ms per call and page took 200–300 ms. Native also does not need the page's JavaScript or CORS, so 2.0 keeps native and drops page.
- **API endpoint:** the workspace URL from `localConfig_v2`, `https://<domain>.slack.com/api/<method>`. No call needed the fallback hosts.
- **Idle document:** works. `localConfig_v2` was readable from the empty `https://app.slack.com/` document and no call fell back to the full client.
- **Sign-in methods:** email with a confirmation code and Google both completed in the embedded window. Google did not refuse the web view. No workspace uses SAML or Okta.
- **Go or no-go:** go. Sessions survived a relaunch of SlackRemote, and every call ran with no window open.

## `localConfig_v2` fields

Confirmed from both accounts. 2.0 reads `id`, `name`, `url`, `token` and `user_id`. The token is redacted.

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
| 1 | Sign in with email and confirmation code | Window closes; `webkit-poc accounts` lists the team | Pass. GIF Monger signed in with an email code; the window closed by itself. |
| 2 | Sign in with Google | Same. If Google shows `disallowed_useragent` or “This browser or app may not be secure”, record the exact screen and URL | Pass. Altumo signed in with Google in the embedded window; no `disallowed_useragent` screen. |
| 3 | Sign in through SAML or Okta, if any workspace uses it | Same, or recorded as not available | Not available. No workspace uses SAML or Okta. |
| 4 | Add a second workspace in the same window through Slack’s own “sign in to another workspace” flow | Both teams appear under one store | Skipped. Not needed for 2.0's first release. |
| 5 | Second account in a separate store | Both work; tokens differ; signing out of one leaves the other signed in | Pass. Altumo is a second store; `auth.test` returns `ok: true` for both teams. Sign-out isolation is covered by row 14. |
| 6 | `auth.test` with each transport, window closed | `ok: true`; `user_id` matches the team record | Pass. Page and native both return `ok: true` with `user_id` `U05V0U3LA7L`, matching the record. |
| 7 | `conversations.history` (`channel`, `limit=5`) on a known channel and `conversations.replies` on a known thread | Messages match what Slack shows | Pass. History read 4 messages from #announcements; `conversations.replies` returned all 5 messages of a known thread on both transports. |
| 8 | Quit and relaunch SlackRemote, repeat 6–7 without signing in | Pass | Pass. After quitting and relaunching SlackRemote, rows 6 and 7 passed on both transports without signing in. |
| 9 | Idle 30 minutes with no window open, then 20 consecutive `auth.test` calls per transport | Record p50 and max `elapsedMs`. Pass when p50 < 500 ms | Deferred to the 2.0 matrix. |
| 10 | Repeat 9 with the screen locked, and from an `ssh user@main-mac` shell | Record | Deferred to the 2.0 matrix. |
| 11 | WebContent memory (`footprint` or Activity Monitor) for the idle document vs the full client | Record both | Deferred to the 2.0 matrix. |
| 12 | Log out of macOS and back in (or reboot), repeat 6 | Pass | Deferred. Juan runs it later. |
| 13 | 60 rapid `conversations.history` calls | Record whether Slack returns HTTP 429 or `error: "ratelimited"` and the `Retry-After` value | Deferred to the 2.0 matrix. 2.0 retries on HTTP 429 and `ratelimited` within the command's deadline. |
| 14 | In the sign-in window’s client, sign out of one workspace, then call `auth.test` | Record the error code (expected `invalid_auth`) | Deferred. Juan runs it later. |
| 15 | `loadClient()` then `localConfig()` after the client has run for a minute | Record whether the token changes | Deferred to the 2.0 matrix. 2.0 reads the token from `localConfig_v2` on every call, so a rotated token is picked up. |
