# v1.0 foundation validation

The live probes ran on main-mac against stock Slack 4.53.292. They held the CLI lock from setup through cleanup and retained only structural observations and command statuses.

| Check | Observation |
| --- | --- |
| Named destinations | A single rendered channel row matched `notes`. The independently marked self-DM matched the prior verified handoff. A second marked row had a non-conversation DOM ID. The CLI saved both names in a separate mode-`0600` config with write restrictions enabled. |
| Informational tooltip | A pre-existing tooltip exposed `ReactModal__Content`, the `AXUserInterfaceTooltip` subrole, and `c-popover__content`. The primary message list, editor, and send control each remained available. In a separately authorized setup probe, its sole backdrop acknowledged `AXPress`, but the tooltip remained present. The tooltip exposed no dismiss action. The CLI now ignores this structure when the primary view remains present. |
| Inspect | All five scopes succeeded. The window, primary view, and tooltip scopes returned only structural fields. No secondary pane or native sheet was open. |
| Write restriction | A dry-run send addressed to the unrelated conversation Slack was showing returned `write_not_allowed` (15) before opening a tree session. |
| Search popup ownership | Opening Slack search also surfaced a coachmark. The first `whoami` run reported `overlay_left_open`. The probe confirmed that the search popup independently exposed one valid-looking self filter and that its specifically identified backdrop closed search and restored the primary view. The probe did not press the coachmark or tooltip. |
| Self navigation | The client arrived at `self`, where a distinct interactive popup appeared. The CLI refused to continue through it. Structural inspection confirmed that the popup was outside the informational-tooltip exception. |
