<!-- title: Foundation: Swift package, Accessibility session, safety gates, and the doctor, current and open commands -->

`slack-remote` is a macOS command-line tool that controls the stock Slack desktop client in the user's logged-in session. It uses two mechanisms only: Slack's documented `slack://` links, and macOS Accessibility (`AXUIElement` reads and semantic actions such as `AXPress`). This issue builds the package, the Accessibility layer, every safety gate the later commands rely on, and three commands: `doctor`, `current` and `open`.

Two later issues add `read` and then `draft`/`send`. They depend on the types and locators defined here, so keep the names and shapes below exactly.

## Hard boundaries

These apply to every issue in the project.

- No Slack Web API, no browser Slack, no Slack app registration, no tokens, no reading Slack's files, cookies or storage.
- No synthetic mouse or keyboard events (`CGEvent`, `CGEventPost`, AppleScript `keystroke`, `System Events`). No code injection, no debugging port, no relaunching Slack with flags.
- Accessibility reads and semantic actions only: `AXPress`, and setting `AXValue`, `AXFocused`, `AXSelectedText`, `AXSelectedTextRange` and `AXManualAccessibility`.
- The tool never prompts for or grants the Accessibility permission. It reports the state and stops.
- Do not add CI workflows.
- Do not write message text, names or URLs to disk or to diagnostics. Command results go to stdout only.

## Stack

- Swift, one SwiftPM package, `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v5]` on every target. The tool is single-threaded and synchronous; language mode 5 avoids `Sendable` friction with CoreFoundation Accessibility types.
- One dependency: `https://github.com/apple/swift-argument-parser` from `1.5.0`.
- Tests use Swift Testing (`import Testing`), run with `swift test`.
- System frameworks: `ApplicationServices`, `AppKit`, `CoreGraphics`.

## Layout and file ownership

This issue creates every file below.

```
Package.swift
.gitignore                         (.build/, .swiftpm/, *.xcodeproj)
README.md                          (replace the existing two-line file)
Sources/slack-remote/              executable target named "slack-remote"
  Main.swift                       root command, subcommand list
  CommandSupport.swift             shared options, JSON output, error-to-exit mapping
  Commands/Doctor.swift
  Commands/Current.swift
  Commands/Open.swift
Sources/SlackRemoteCore/           library target, all logic
  UINode.swift                     tree protocol, attribute and action enums, search helpers
  AXNode.swift                     AXUIElement-backed UINode
  Environment.swift                GUI session, lock screen, trust, idle time
  SlackApp.swift                   process lookup, version, tree enable and restore
  CommandLock.swift                one invocation at a time
  Poll.swift                       deadline polling
  Locators.swift                   every locator constant for the whole project
  Destination.swift                id types, URL parsing, deep-link building
  SlackWindow.swift                client window resolution, location, destination verification
  Navigator.swift                  navigation routes and focus restore
  RemoteError.swift
Tests/SlackRemoteCoreTests/
  Support/FakeNode.swift
  Support/SlackFixture.swift
  DestinationTests.swift
  SlackWindowTests.swift
  NavigatorTests.swift
  SlackAppTests.swift
docs/validation/foundation.md
```

## What was observed on the real client

Slack 4.53.292 on macOS 27.2.1 was probed for structure only. These facts are the basis for the design; rely on them.

- With default settings Slack exposes 12 nodes and no web content. Setting the attribute `AXManualAccessibility` to `true` on Slack's application element makes the web tree appear about 2.1 s later. Setting it back to `false` removes the tree again.
- Reading `AXManualAccessibility` returns `false` at all times, even right after setting it to `true`. Never use its value. The tree is "on" when an `AXWebArea` exists under a Slack window.
- The populated window is about 440 nodes, depth 30. A full walk that reads role, subrole, `AXDOMClassList`, `AXDOMIdentifier` and `AXChildren` with one `AXUIElementCopyMultipleAttributeValues` call per node takes about 0.07 s. Walk the whole tree freely; do not build search optimisations.
- The window has exactly one `AXWebArea`. Its `AXURL` is `https://app.slack.com/client/<TEAM_ID>/<CONVERSATION_ID>`.
- Sidebar conversation rows are `AXRow` / `AXOutlineRow` nodes with class `p-channel_sidebar__static_list__item` and `AXDOMIdentifier` equal to the conversation id. The open conversation's row also has class `p-channel_sidebar__static_list__item--selected`. The sidebar is virtualised: a conversation scrolled out of view has no row.
- Slack's documented links are `slack://open`, `slack://open?team={TEAM_ID}`, `slack://channel?team={TEAM_ID}&id={CHANNEL_ID}` and `slack://user?team={TEAM_ID}&id={USER_ID}`. No documented link targets a message or thread.

Not yet observed, and settled by this issue's live validation: opening a `slack://` link, pressing a sidebar row, behaviour when Slack is hidden or minimised, and behaviour from an ssh shell.

## Tree abstraction

All logic reads the UI through a protocol so it can be tested against a fake tree.

```swift
public enum UIAttribute: String {
    case title = "AXTitle"
    case description = "AXDescription"
    case value = "AXValue"
    case url = "AXURL"
    case enabled = "AXEnabled"
    case focused = "AXFocused"
    case main = "AXMain"
    case minimized = "AXMinimized"
    case selectedText = "AXSelectedText"
    case selectedTextRange = "AXSelectedTextRange"
}

public enum UIAction: String { case press = "AXPress" }

public enum UIValue: Equatable {
    case string(String)
    case bool(Bool)
    case range(location: Int, length: Int)
}

public protocol UINode {
    var role: String { get }
    var subrole: String? { get }
    var domClasses: [String] { get }
    var domID: String? { get }
    var children: [any UINode] { get }
    func string(_ attribute: UIAttribute) -> String?
    func bool(_ attribute: UIAttribute) -> Bool?
    func set(_ attribute: UIAttribute, to value: UIValue) throws
    func perform(_ action: UIAction) throws
}

public extension UINode {
    /// Depth-first, document order, excluding self.
    func descendants() -> [any UINode]
    func all(_ locator: Locator) -> [any UINode]
    /// Throws RemoteError.uiDrift(locator: locator.name, found: n) unless exactly one node matches.
    func one(_ locator: Locator) throws -> any UINode
}
```

`AXNode` implements `UINode` over an `AXUIElement`.

- At init it reads `AXRole`, `AXSubrole`, `AXDOMClassList`, `AXDOMIdentifier` and `AXChildren` in one `AXUIElementCopyMultipleAttributeValues` call (options `0`). A missing attribute comes back as an `AXValue` of type `.axError`; treat that, and `NSNull`, as nil.
- `children` builds child `AXNode`s lazily.
- Other attributes are read live. `AXURL` arrives as a `CFURL`; return its `absoluteString`.
- A range is written with `AXValueCreate(.cfRange, &range)`.
- A failed `set` or `perform` throws `RemoteError.axFailure(operation:code:)`.
- A node is a snapshot. After any action, link, or wait, resolve nodes again from the window root. Never reuse a node across a state change.

## Locators

A locator matches on role, subrole, required classes and an optional id. Titles and descriptions are localised and must never be used to find an element.

```swift
public struct Locator {
    public let name: String          // used in ui_drift diagnostics
    public let role: String
    public var subrole: String? = nil
    public var classes: [String] = []    // every listed class must be present
    public var idPrefix: String? = nil
    public func matches(_ node: any UINode) -> Bool
}
```

`Locators.swift` holds every constant for the project, in three sections. Later issues may correct constants in their own section and must not touch the others.

| Section | Constant | Role | Subrole | Classes | Id |
|---|---|---|---|---|---|
| Shell | `webArea` | `AXWebArea` | | | |
| Shell | `sidebarRow` | `AXRow` | `AXOutlineRow` | `p-channel_sidebar__static_list__item` | conversation id |
| Shell | `primaryView` | `AXGroup` | | `p-view_contents--primary` | |
| Messages | `messageList` | `AXList` | `AXContentList` | | |
| Messages | `messageItem` | `AXGroup` | | `c-virtual_list__item` | prefix `message-list_` |
| Messages | `messageBody` | `AXGroup` | `AXDocument` | `c-message_kit__hover` | |
| Messages | `senderButton` | `AXButton` | | `c-message__sender_button` | |
| Messages | `richTextSection` | `AXGroup` | | `p-rich_text_section` | |
| Messages | `reaction` | `AXCheckBox` | `AXToggleButton` | `c-reaction` | |
| Composer | `composerEditor` | `AXTextArea` | | `ql-editor` | |
| Composer | `sendButton` | `AXButton` | | `c-wysiwyg_container__button--send` | |

Class-name constants, also in `Locators.swift`: `sidebarRowSelected = "p-channel_sidebar__static_list__item--selected"`, `sidebarDraft = "p-channel_sidebar__channel--draft"`, `reactionReacted = "c-reaction--reacted"`, `composerBlank = "ql-blank"`, `buttonDisabled = "c-button--disabled"`, and the prefix `attachmentPrefix = "c-message_attachment"`.

## Identifiers and locations

```swift
public struct TeamID: Hashable { public let rawValue: String }          // ^[TE][A-Z0-9]{8,}$
public struct ConversationID: Hashable { public let rawValue: String }  // ^[CDG][A-Z0-9]{8,}$
public struct UserID: Hashable { public let rawValue: String }          // ^[UW][A-Z0-9]{8,}$
public struct Destination: Hashable {
    public let team: TeamID
    public let conversation: ConversationID
}

public enum ClientLocation: Equatable {
    /// trailing holds any path segments after the conversation id, e.g. ["thread", "..."].
    case conversation(Destination, trailing: [String])
    /// A client view that is not a conversation, e.g. the Threads or search view.
    case other(team: TeamID, path: [String])
    /// Not the Slack client at all, e.g. a sign-in page.
    case notClient

    public static func parse(url: String) -> ClientLocation
}
```

Each id type has a failable `init?(_ raw: String)` that applies the regex. `ConversationID` exposes `kind`: `.channel` for `C`, `.directMessage` for `D`, `.group` for `G`.

`parse` requires scheme `https`, host `app.slack.com` and a first path segment `client`. Worked examples, all with invented ids. The second row only shows how trailing segments are kept; the real URL of an open thread has not been observed.

| URL | Result |
|---|---|
| `https://app.slack.com/client/T0AAAAAAA/C0BBBBBBB` | `.conversation(T0AAAAAAA / C0BBBBBBB, trailing: [])` |
| `https://app.slack.com/client/T0AAAAAAA/D0CCCCCCC/thread/D0CCCCCCC-1700000000.000100` | `.conversation(T0AAAAAAA / D0CCCCCCC, trailing: ["thread", "D0CCCCCCC-1700000000.000100"])` |
| `https://app.slack.com/client/T0AAAAAAA/threads` | `.other(team: T0AAAAAAA, path: ["threads"])` |
| `https://app.slack.com/client/T0AAAAAAA` | `.other(team: T0AAAAAAA, path: [])` |
| `https://app.slack.com/signin` | `.notClient` |
| `https://example.com/client/T0AAAAAAA/C0BBBBBBB` | `.notClient` |

Deep links, built by `Destination.swift`:

- `slack://channel?team=<TEAM_ID>&id=<CONVERSATION_ID>`
- `slack://user?team=<TEAM_ID>&id=<USER_ID>`

## Preflight

Every command runs these checks in this order before touching Slack, and stops at the first failure.

1. GUI session. `CGSessionCopyCurrentDictionary()` must be non-nil with `kCGSSessionOnConsoleKey` true. Otherwise `no_gui_session`. A process started over ssh has no GUI session; the tool must be started from a process inside the user's login session, such as a terminal app on that Mac.
2. Screen lock. If the dictionary has `CGSSessionScreenIsLocked` true, fail with `screen_locked`. The key is absent when unlocked.
3. Accessibility trust. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])` must be true. Otherwise `accessibility_not_trusted`, with a message telling the user to enable the app that launched the tool under System Settings › Privacy & Security › Accessibility.
4. Slack process. `NSRunningApplication.runningApplications(withBundleIdentifier: "com.tinyspeck.slackmacgap")` must return exactly one app that has finished launching. Zero is `slack_not_running`; more than one is `ambiguous_slack`. The tool never launches Slack.
5. Visibility. If the app `isHidden`, fail with `slack_window_unavailable`.
6. Version. Read `CFBundleShortVersionString` from the running app's bundle. If it does not start with one of `SlackApp.testedVersionPrefixes` (initially `["4.53."]`), add the warning `untested_slack_version` and continue. Structure checks are the gate; the version is information.

## Command lock

Only one invocation may drive Slack at a time. `CommandLock` opens `~/Library/Application Support/slack-remote/lock` (create the directory with mode `0700`) and takes `flock(fd, LOCK_EX | LOCK_NB)`, retrying every 100 ms until the command deadline. On deadline it throws `busy`. The lock is held until the process exits; the kernel releases it if the process dies, so there is no stale-lock handling.

## Tree session

`SlackApp` owns turning the tree on and off.

```swift
public final class SlackApp {
    /// Runs body with the window roots available, then restores the previous mode on every exit path.
    public func withTree<T>(deadline: Date, _ body: (SlackTree) throws -> T) throws -> T
}
```

Behaviour:

1. Create the application element with `AXUIElementCreateApplication(pid)` and call `AXUIElementSetMessagingTimeout(app, 2.0)`.
2. Delete any marker file in `~/Library/Application Support/slack-remote/` named `ax-enabled-<pid>` whose pid is not the current Slack pid.
3. Decide ownership. If an `AXWebArea` already exists under a window and there is no marker for this pid, another assistive tool turned the tree on: do not change the mode and do not restore it. Otherwise this run owns the mode.
4. If this run owns the mode and the tree is absent, write the marker file, then set `AXManualAccessibility` to `kCFBooleanTrue` on the application element.
5. Poll every 100 ms until the tree is settled: a window contains a `webArea`, and two consecutive full walks return the same node count. If the deadline passes, restore and throw `tree_unavailable`.
6. Run `body`.
7. On every exit path, if this run owns the mode: set `AXManualAccessibility` to `kCFBooleanFalse` and delete the marker.

Restore must also run on `SIGINT`, `SIGTERM` and `SIGHUP`. Ignore the default disposition with `signal(sig, SIG_IGN)`, install a `DispatchSource.makeSignalSource(signal:queue: .main)` for each, and have the handler restore and call `exit(130)`. `Poll` must wait with `RunLoop.main.run(until:)` so these handlers fire while a command is waiting.

`SlackTree` gives access to the window nodes and to `refresh()`, which re-reads them.

## Client window and destination verification

`SlackWindow.swift` provides:

```swift
/// The Slack windows whose web area URL parses to .conversation or .other.
func clientWindows(in tree: SlackTree) -> [ClientWindow]

/// The window `current` reports: the only client window, or the only one with AXMain true.
/// Zero client windows throws slack_not_ready; an undecidable set throws ambiguous_window.
func currentWindow(in tree: SlackTree) throws -> ClientWindow

/// Returns the verified window, or throws destination_mismatch / ambiguous_window / ui_drift.
func verify(_ destination: Destination, in tree: SlackTree) throws -> VerifiedView
```

`verify` passes only when all of these hold:

1. Exactly one client window has a location of `.conversation` whose team and conversation both equal the destination. Trailing path segments are allowed.
2. That window is not minimised (`AXMinimized` is not true). Otherwise `slack_window_unavailable`.
3. That window contains exactly one `primaryView`.
4. If any `sidebarRow` in that window has the selected class, its `domID` equals the destination's conversation id. No selected row is acceptable, because the sidebar is virtualised.

`VerifiedView` carries the destination, the window node and the primary view node. Later issues take a `VerifiedView` as proof that the destination was checked, and re-run `verify` immediately before each mutating step.

`destination_mismatch` carries the expected ids and the actual location in its details.

## Human-in-use gate

`Environment.secondsSinceUserInput()` returns `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`.

Slack is "in use" when it is the frontmost application and the last user input was less than 30 seconds ago. A command that would change the conversation, focus or composer fails with `slack_in_use` in that case, unless `--interrupt` is passed. `doctor`, `current`, and `open` or `read` calls that need no navigation are never blocked by this gate.

## Navigation

```swift
public struct Navigator {
    public init(openLink: @escaping (URL) throws -> Void,
                frontmostBundleID: @escaping () -> String?,
                activate: @escaping (_ bundleID: String) -> Void,
                secondsSinceUserInput: @escaping () -> Double)
    public func navigate(to destination: Destination, user: UserID?, interrupt: Bool,
                         in tree: SlackTree, deadline: Date) throws -> NavigationResult
}

public struct NavigationResult: Encodable {
    public let route: Route          // already_there, deep_link_channel, deep_link_user, sidebar_row
    public let focusRestored: Bool
}
```

Steps:

1. If `verify` already passes, return `already_there` without doing anything.
2. Apply the human-in-use gate.
3. Remember the frontmost application.
4. Pick one route. There is no fallback from one route to another within a call.
   - Conversation id starts with `C`: open `slack://channel?team=…&id=…`.
   - Conversation id starts with `D` and `user` is given: open `slack://user?team=…&id=…`.
   - Otherwise: find the `sidebarRow` whose `domID` equals the conversation id and `perform(.press)` on it. If no such row is rendered, throw `destination_unreachable` with a message suggesting `--user` for a DM.
5. Poll: refresh the tree and run `verify` every 100 ms until it passes and the tree is settled, or the deadline passes. On deadline throw `destination_mismatch`.
6. If the remembered frontmost application was not Slack and Slack is now frontmost, activate the remembered application again and set `focusRestored` to true.

The production `openLink` calls `NSWorkspace.shared.open([url], withApplicationAt: slackBundleURL, configuration: config)` with `config.activates = false`, where `slackBundleURL` is the running Slack's `bundleURL`. This sends the link to the running stock client and asks macOS not to bring it forward.

The verification in step 5 is what makes navigation safe. The route only gets Slack there; nothing is trusted until the web area URL shows the exact team and conversation ids.

## Commands

Global options on every command: `--timeout <seconds>` (default `15`, one deadline for the whole command) and `--debug` (prints locator names, match counts and timings to stderr; never text, names or URLs).

Every command runs: preflight, lock, tree session, work, restore.

### `slack-remote doctor`

Reports the state of every prerequisite. It never navigates. It runs all checks it can, prints the full result, and exits `0` only if every check passed; otherwise it exits with the code of the first failed check.

```json
{
  "ok": true,
  "command": "doctor",
  "slackVersion": "4.53.292",
  "warnings": [],
  "result": {
    "checks": [
      { "name": "gui_session", "ok": true },
      { "name": "screen_unlocked", "ok": true },
      { "name": "accessibility_trusted", "ok": true },
      { "name": "slack_running", "ok": true },
      { "name": "slack_visible", "ok": true },
      { "name": "tree_available", "ok": true, "detail": "enabled by this run, settled in 2.3 s, 438 nodes" },
      { "name": "client_window", "ok": true },
      { "name": "locators", "ok": true, "detail": "webArea=1 primaryView=1 composerEditor=1 sendButton=1 messageList=1" }
    ]
  }
}
```

The `locators` check counts matches inside the current client window: `webArea`, `primaryView`, `composerEditor` and `sendButton` inside the primary view, `messageList` inside the primary view. It passes when each count is exactly 1. When the current view is not a conversation, report `ok: true` with detail `not a conversation view` and skip the counts.

### `slack-remote current`

Prints where the client is. It never navigates.

```json
{
  "ok": true, "command": "current", "slackVersion": "4.53.292", "warnings": [],
  "result": { "view": "conversation", "team": "T0AAAAAAA", "conversation": "C0BBBBBBB", "kind": "channel", "trailing": [] }
}
```

For a non-conversation view: `{ "view": "other", "team": "T0AAAAAAA", "path": ["threads"] }`.

### `slack-remote open --team <TEAM_ID> --channel <CONVERSATION_ID> [--user <USER_ID>] [--interrupt]`

Navigates to the conversation and verifies it. `--channel` accepts any conversation id (`C…`, `D…`, `G…`) and is always required, because it is the exact check. `--user` only selects the documented DM link.

```json
{
  "ok": true, "command": "open", "slackVersion": "4.53.292", "warnings": [],
  "result": { "team": "T0AAAAAAA", "conversation": "C0BBBBBBB", "route": "deep_link_channel", "focusRestored": false }
}
```

Put the destination flags in one shared `ParsableArguments` type in `CommandSupport.swift`; `read`, `draft` and `send` reuse it.

## Output and errors

Success goes to stdout as the envelope shown above, encoded with `JSONEncoder` using `.prettyPrinted` and `.sortedKeys`. Failure goes to stderr:

```json
{ "ok": false, "command": "open", "error": { "code": "destination_mismatch", "message": "Slack did not arrive at the requested conversation.", "details": { "expectedTeam": "T0AAAAAAA", "expectedConversation": "C0BBBBBBB", "actual": "conversation T0AAAAAAA/C0DDDDDDD" } } }
```

`RemoteError` is one enum. Each case maps to one code string and one exit status. Define all of them now; later issues use the ones marked with their number.

| Exit | Codes |
|---|---|
| 0 | success |
| 1 | `internal`, `ax_failure` |
| 10 | `no_gui_session`, `screen_locked`, `accessibility_not_trusted` |
| 11 | `slack_not_running`, `ambiguous_slack`, `slack_window_unavailable`, `slack_not_ready`, `tree_unavailable` |
| 12 | `ui_drift`, `ambiguous_window`, `ui_blocked` (Issue 3) |
| 13 | `destination_mismatch`, `destination_unreachable` |
| 14 | `slack_in_use`, `busy` |
| 15 | `unsafe_text`, `draft_conflict` (Issue 3) |
| 16 | `write_failed`, `write_unverified`, `send_not_performed` (Issue 3) |
| 17 | `send_unconfirmed` (Issue 3) |
| 18 | `timeout` |
| 64 | argument errors, produced by ArgumentParser |

Invalid ids are argument errors: validate them in the option types so ArgumentParser rejects them.

## Tests

`FakeNode` is a class implementing `UINode` with mutable role, subrole, classes, id, children and an attribute dictionary, plus optional closures `onSet` and `onPerform` so a test can script a reaction to an action. It records every `set` and `perform` call.

`SlackFixture` builds a fake Slack window from parameters and is reused by later issues:

```swift
SlackFixture.window(
    team: "T0AAAAAAA", conversation: "C0BBBBBBB",
    sidebar: ["C0BBBBBBB", "D0CCCCCCC"],      // rows; the row matching `conversation` gets the selected class
    isMain: true
) -> FakeNode
```

The fixture mirrors the observed nesting: window, groups, `AXWebArea` with the URL, sidebar rows, a primary view containing a message list, one composer editor with the blank class and one disabled send button. All ids and text in fixtures are invented.

Write these tests and no others:

- `DestinationTests`: the six URL examples above; id validation accepting and rejecting one case per type; both deep-link strings.
- `SlackWindowTests`: `verify` passes on a matching window; fails with `destination_mismatch` on a different conversation; fails when the selected sidebar row disagrees with the URL; passes when no row is selected; fails with `ambiguous_window` when two windows show the destination; `currentWindow` picks the main window of two.
- `NavigatorTests`, with an injected `openLink` and a fake tree that changes its URL when the link or row is used: channel id opens the channel link; DM id with a user opens the user link; DM id without a user presses the row; missing row throws `destination_unreachable`; already-there opens nothing; a tree that never changes throws `destination_mismatch` at the deadline; `slack_in_use` is thrown when Slack is frontmost with recent input and `interrupt` is false.
- `SlackAppTests`, with the mode-setting and tree-presence calls injected: a tree that is already present without a marker is neither enabled nor restored; a tree this run enabled is restored when `body` throws.

`swift test` must not touch the real Slack client.

## Live validation

Write the results to `docs/validation/foundation.md`. Record ids and outcomes only; never paste names, message text or URLs.

Allowed on any workspace, because they only read and never navigate:

1. `swift build -c release`, then `.build/release/slack-remote doctor`. Record each check result, the settle time and node count.
2. `slack-remote current`. Confirm it matches the conversation on screen.
3. After each command, confirm the tree is off again: a second `doctor` run must report `enabled by this run`.
4. Run `doctor` from an ssh shell into the same Mac and record the error code.
5. Start two `current` commands at once and confirm both succeed in turn; start one with `--timeout 0.2` while another holds the lock and confirm `busy`.
6. Press Ctrl-C during the settle wait of a `doctor` run, then run `doctor` again. It must report `enabled by this run`, and no `ax-enabled-*` marker may remain.
7. Run `sleep 10; slack-remote current`, lock the screen within the ten seconds, and record the result after unlocking. Expected: `screen_locked`, exit status 10.

Allowed only against the disposable destination. It is supplied through the environment variables `SLACK_REMOTE_TEST_TEAM` and `SLACK_REMOTE_TEST_CHANNEL`, and optionally `SLACK_REMOTE_TEST_DM` with `SLACK_REMOTE_TEST_USER`. If they are not set, do not run these steps, do not choose a destination yourself, and say so in the pull request.

8. `open` to the test channel from another conversation. Record the route, whether Slack came to the front, and whether `focusRestored` was true.
9. `open` to the test DM with `--user`, and again without `--user`. Record whether the user link landed on the expected `D…` id.
10. `open` with a valid-looking conversation id that does not exist. Confirm `destination_mismatch` and exit status 13.
11. With Slack minimised, and again with Slack hidden, run `current`. Record what happens. If the tree is unavailable in either state, the error must be `slack_window_unavailable` or `tree_unavailable`.

## Acceptance criteria

- `swift build -c release` and `swift test` succeed on macOS 27 with Xcode 27.
- `doctor`, `current` and `open` produce the JSON shapes above and the exit statuses in the table.
- After any command, including one interrupted with Ctrl-C, Slack's web tree is off again when the command turned it on, and no marker file remains.
- `open` reports success only when the web area URL holds exactly the requested team and conversation ids.
- No locator uses a title, description or other localised string.
- The package contains no `CGEvent` use, no AppleScript, no network code and no CI workflow.
- `README.md` describes the tool in one paragraph, the Accessibility permission and GUI-session requirement, the build command, the three commands with one example each, and the exit status table.
- `docs/validation/foundation.md` records the live validation steps that were run, their outcomes, and which were skipped and why.
