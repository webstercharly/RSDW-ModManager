# UI specification

## Entry points

- `Esc > MOD MANAGER` in the Dragonwilds pause menu.
- Configurable open key, initially `F7`.

## Visual direction

Use a compact RuneScape-like panel. Important actions and state should be
visible without scrolling through deeply nested service names.

## Main screen

```text
┌ MOD MANAGER ──────────────────────────────────────────────────────┐
├──────────────────┬────────────────────────────────────────────────┤
│ scrollable mods  │ selected module                                │
│ [MODULE A]       │                                                │
│ [MODULE B]       │ rows / module content                          │
│ [...]            │                                                │
│                  │                                                │
├──────────────────┼────────────────────────────────────────────────┤
│                  │ selected row detail                            │
│ [RELOAD MODS]    │                                                │
│                  │ [input field]                                  │
│                  │ [ACTION] [ACTION] [ACTION] ...                 │
└──────────────────┴────────────────────────────────────────────────┘
```

Every module shares the native manager window but remains a separate module in
navigation and behaviour. The module rail is vertically scrollable and must
remain usable with at least 20 installed modules. With no modules installed the
panel says so and explains how to add one. Text input uses a dark background
with cream text and a brighter focused state.

Module-specific screens are specified in each module's own repository.

## Shell rules

- Module names, labels, ordering and actions come from manifests; the shell hardcodes none.
- The entry list is the flexible middle section. The input field and actions stay anchored at the bottom.
- Wrapped detail text uses its natural height and is never clipped.
- Global outcomes such as module reloads go to the transient header notification and never replace module instructions.
- Escape closes the manager; there is no redundant Close action.
- Navigation is reversible: every drilled-in view has an explicit back row.

## Input policy

- Defaults must not require Shift, because Shift is the sprint input. The manager opens with `F7` initially.
- The editor rejects duplicate key combinations and explains conflicts.

## Accessibility

- Mouse and keyboard navigation; controller navigation is intentionally out of scope.
- Colour is never the sole indication of state.
- Destructive actions require confirmation; normal apply actions do not.
