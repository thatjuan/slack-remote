# Amendments to issues 1 to 3

The second probe round contradicted four details in the filed MVP issues. Each amendment below is the smallest change that makes the contract match what Slack does. Everything else in issues 1 to 3 stands, and the MVP keeps its wave plan.

Post each one as a comment on its issue. If the issue's pull request has already merged without it, issue 5 applies the change; its body says so.

## Issue 1: the sidebar route must press the inner group

Observed: `AXPress` on the sidebar `AXRow` returns success and does not navigate. `AXPress` on the `AXGroup` with class `p-channel_sidebar__channel` inside that row navigates in 0.2 s.

Change: in `Navigator`, the `sidebar_row` route finds the `sidebarRow` whose `domID` equals the conversation id, then finds exactly one descendant `AXGroup` with class `p-channel_sidebar__channel` and performs `.press` on that. Add the locator `sidebarRowTarget` (role `AXGroup`, class `p-channel_sidebar__channel`) to the Shell section of `Locators.swift`. The row is still what verification reads.

## Issue 1: the channel link works for every conversation id

Observed: `slack://channel?team=…&id=…` navigated to a `G…` id and to a `D…` id, each in 0.2 s, with the URL and selected row matching.

Change: route selection becomes

1. `--user` given and the conversation id starts with `D`: `slack://user`.
2. Otherwise, for any conversation id: `slack://channel`.

The `sidebar_row` route stays in the code and is used only when `--route sidebar` is passed, so it remains testable. `destination_unreachable` now applies only to that route. Verification is unchanged and still decides success.

## Issue 1: tree readiness needs a parseable URL, and the tree can vanish

Observed: when another process cleared `AXManualAccessibility` during a probe, the web area existed for several seconds with no URL, or the tree disappeared partway through a run.

Changes:

- In `SlackApp.withTree`, "settled" means: a window contains a `webArea` whose `AXURL` parses to something other than `.notClient`, and two consecutive full walks 100 ms apart return the same node count.
- `SlackTree.refresh()` throws `tree_unavailable` when no window contains a `webArea` with a parseable URL. Every command already refreshes before acting, so a tree removed by another tool stops the command.
- Add to the README: other assistive tools that toggle Slack's accessibility mode can make a command fail with `tree_unavailable`; rerun it.

## Issue 3: what counts as a blocking dialog

Observed:

- Every Slack popup that was opened is a node with class `ReactModal__Content`: the message menu, the emoji picker, the channel details modal and the search modal.
- The native file panel is an `AXSheet`.
- The thread pane is an `AXGroup` with subrole `AXApplicationDialog` and class `p-view_contents--secondary`. Under issue 3's rule, an open thread pane would block every write.
- While a `ReactModal__Content` popup is open, the primary view is missing from the tree.

Change: a blocking dialog exists when the Slack window contains a node with class `ReactModal__Content`, or a node with role `AXSheet`. Subroles are not used. Run this check before `SlackWindow.verify` in the write path, so the caller gets `ui_blocked` and not a `ui_drift` caused by the hidden primary view. Add the class constant `modalContent = "ReactModal__Content"` to `Locators.swift`.

## No change needed

- Destination verification by web area URL and selected sidebar row held in every navigation.
- The composer and send button locators matched exactly once in the channel, the DM and, separately, the thread pane.
- Message item ids matched `message-list_<ts>` in both destinations.
