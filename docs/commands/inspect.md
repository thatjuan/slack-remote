# inspect

```sh
slack-remote inspect [--scope window|primary|secondary|modal|sheet] [--max-depth N] [--emoji-names]
```

Prints one line per Accessibility node with its indentation, role, subrole, DOM classes, DOM ID, action names, and settable `AXValue`, `AXFocused`, and `AXSelectedText` attributes. The default scope is `window`, and depth starts at zero for each scope root. An absent scope yields empty output.

Output is plain text. DOM identifier runs of at least eight uppercase letters or digits beginning with a letter, and digit runs of at least six, are masked. For example, `C0BBBBBBB` becomes `C§9`. Traversal stops at editable text area and combo box nodes. Descriptions, values, and URLs are absent from the output. `--emoji-names` includes titles only on `c-emoji` images whose title is an exact Slack shortcode.

`inspect` also works with a modal or sheet open. A missing client tree returns `tree_unavailable`, and several windows without a unique main window return `ambiguous_window`.
