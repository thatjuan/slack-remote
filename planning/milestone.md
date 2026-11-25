A local macOS command-line tool that controls the stock Slack desktop client in the user's logged-in session, using Slack's documented `slack://` links and macOS Accessibility reads and semantic actions. It uses no Slack API, no browser Slack, no app registration, no credentials, no synthetic mouse or keyboard events, and does not modify or inject into the Slack process.

v0.1 delivers six commands:

- `doctor` reports whether the session, the Accessibility permission, Slack and its UI structure are usable.
- `current` reports the team and conversation ids Slack is showing.
- `open` navigates to a conversation and succeeds only when Slack's own URL shows the requested ids.
- `read` returns the messages Slack has rendered in a conversation.
- `draft set` and `draft clear` write and remove a draft in a verified conversation.
- `send` posts a message to a verified conversation, when explicitly invoked.

Every write is gated on an exact check of the team and conversation ids immediately before it happens. An unexpected state stops the command: a different conversation, an existing draft, a blocking dialog, a changed UI structure, a locked screen, a person actively using Slack, or a second invocation. Sends are pressed once, never retried, and reported as unconfirmed when the result cannot be established.

Thread replies and reactions are outside this milestone. A separate optional issue covers them, limited to the paths that can be targeted by message id.

Done when the three milestone issues are merged, `swift test` passes, and the read-only validation in each issue has been run on Slack 4.53 or later. Live navigation, draft and send checks run only against a disposable destination that Juan designates.
