# v1.0 foundation validation

The live probes ran on main-mac against stock Slack 4.53.292. They held the CLI lock from setup through cleanup and retained only structural observations and command statuses.

| Check | Observation |
| --- | --- |
| Named destinations | A single rendered channel row matched `notes`. The independently marked self-DM matched the prior verified handoff. A second marked row had a non-conversation DOM ID. The CLI saved both names in a separate mode-`0600` config with write restrictions enabled. |
| Informational tooltip | A pre-existing tooltip exposed `ReactModal__Content`, the `AXUserInterfaceTooltip` subrole, and `c-popover__content`. The primary message list, editor, and send control each remained available. In a separately authorized setup probe, its sole backdrop acknowledged `AXPress`, but the tooltip remained present. The tooltip exposed no dismiss action. The CLI now ignores this structure when the primary view remains present. |
| Inspect | All five scopes succeeded. The window, primary view, and tooltip scopes returned only structural fields. No secondary pane or native sheet was open. |
| Write restriction | A dry-run send addressed to the unrelated conversation Slack was showing returned `write_not_allowed` (15) before opening a tree session. |
| Search popup ownership | Opening Slack search also surfaced a coachmark. `whoami --save` returned `overlay_left_open`. A cleanup probe found one valid-looking self filter and confirmed that the search popup's own backdrop closed search and restored the primary view. It left the coachmark and tooltip controls untouched. The private config contains verified aliases and still needs a saved account. |
| Self navigation | The client arrived at `self`, where a distinct interactive popup appeared. Its structure fell outside the informational-tooltip exception. In a separate authorized setup probe, its unique backdrop acknowledged `AXPress`, but the popup stayed open. The probe could not verify focus inside the popup and sent no Escape. The exact destination and draft matched before and after. |
| Remaining live checks | The interactive popup blocked the conversation-start observation, `self` history and scroll restoration, `notes` one-page history and dry run, the temporary account-mismatch check, and the synthetic draft and send checks. The CLI made no composer writes or send presses. |

The release build, all 78 fixture tests, and `git diff --check` passed. The release CLI also passed seven stub checks, four argument error checks, and local config creation, replacement, listing, and permission refusal.

## Follow-up in notes

The documented channel link reached `notes` from `self`. The client URL and selected sidebar row both matched the verified destination, and `notes` showed no blocking modal or sheet. The setup left the existing `self` draft untouched.

| Check | Observation |
| --- | --- |
| Account save | Slack initially exposed the signed-in quick filter without the search portal class or its backdrop. The CLI now locates the popup by its controls and rebuilds an Accessibility session it owns when the backdrop is missing. The reloaded tree exposed two backdrops, and the CLI used the one associated with search. `whoami --save` closed search, returned to `notes`, and saved the independently verified account. |
| Bounded history | `notes` returned one page with `stopReason: "limit"`, timestamps in order with no duplicates, and `scrollRestored: true`. A separate older-history probe stalled after nine pages with no verified conversation-start marker. Multi-page scroll restoration and `self` history remain unverified. |
| Dry run and account mismatch | A permitted send dry run returned the plan and left the empty `notes` composer intact. A temporary mismatch in the saved self-DM returned `account_mismatch` (20). The verified private config was restored. |
| Draft and send | The empty `notes` composer accepted a synthetic draft. A different draft returned `draft_conflict` (15) and preserved the first draft. Exact clear returned the composer to empty. After a fresh destination, account, composer, and rendered-list check, one unique synthetic send returned a confirmed receipt and the composer was empty again. |

The follow-up release build, all 79 fixture tests, and `git diff --check` passed.
