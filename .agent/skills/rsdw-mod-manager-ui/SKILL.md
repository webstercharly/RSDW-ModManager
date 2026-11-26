---
name: rsdw-mod-manager-ui
description: "Build or revise manifest-driven UE4SS modules and shared UI in the standalone RSDWModManager for RuneScape: Dragonwilds. Use for its module menus, interaction design, safe reload behavior, persistence, or gameplay validation; do not apply to unrelated UE4SS mods."
---

# RSDW Mod Manager UI

Work in the installed `RSDWModManager` mod while preserving standalone operation and user data under `%LOCALAPPDATA%\RSDWModManager`.

This project is permanently PC-only. Design and test for keyboard and mouse;
do not propose or implement controller navigation unless the user explicitly
changes that product scope.

## Start with the shared boundary

- Read the target module manifest/runtime, `Scripts/rlm_ui.lua`, and the relevant portions of `README.md`, `Docs/ROADMAP.md`, and `Docs/TEST_PLAN.md` before changing behavior.
- Put reusable layout, navigation, notification, and input behavior in `rlm_ui.lua` once. Do not reproduce shared widgets inside individual modules.
- Keep module names, descriptions, ordering, and actions in each manifest. The shell must discover them rather than hardcoding module-specific controls.
- For a subview with different controls, return `actionIds` from `activate` to choose manifest actions. Use `actionLabels` keyed by action ID for labels that change with the current view. A view can set `inlineActions = true` to place input-free actions below its detail card and above its list. Check `state.uiInlineActions` when supporting an older shell.
- Keep domain operations in the module or its service files. A module runtime should expose only the view and actions the shell needs.

## Follow the established interaction design

- Prefer the smallest task-complete action set. Remove separate Check or Verify actions when Apply already performs preflight and final verification.
- Use short button labels that fit two columns. Put syntax examples in the input hint or one concise instruction line.
- Treat the entry list as the flexible middle section. Keep the name/input field and actions anchored at the bottom; avoid fixed list heights and unnecessary nested scrollbars.
- Let wrapped detail text use its desired height; never place it in a fixed-height container that clips later lines.
- Omit counts and status text that do not change a decision. Use module status only for active context such as a region or search result.
- Send host-wide outcomes such as module reloads to the transient global header notification. Do not overwrite module instructions with global events.
- Use compact rows when full cards would clip or overlap. Retain only decision-relevant information in the row title; reveal detail elsewhere when needed.
- When selecting a row supplies an identifier but an action also needs a value, accept both selected-row plus value and explicit `identifier value` input forms.
- Prefer a short timed capture for keyboard/mouse bindings; poll held and just-pressed states with compatible Unreal mouse-key aliases, keep direct text entry as a fallback, and leave the prior binding unchanged on timeout.
- Sort by domain order, such as progression, numeric swap ID, or style sequence. Do not default to alphabetical order when it obscures gameplay progression.
- Keep navigation reversible. Add an explicit root/back route and avoid Lua's `condition and nil or value` idiom when the intended result can be `nil`.
- Escape closes the manager. Do not add a redundant Close action.

## Preserve reload and gameplay safety

- Never invoke `RestartCurrentMod` from this mod's callback or tick. Refresh manifests/module runtimes through the in-process module loader and rebuild only the panel.
- Once this shell version is running, **Reload Mods** can replace the shell view,
  shared UI Kit and module runtimes in process. Changes to `main.lua`,
  `rlm_bootstrap.lua` or `rlm_modules.lua` still require a normal restart.
- Keep module-specific behaviour in the module's own repository. The shell exposes the module contract in `README.md` (`activate`, `run_action`, `select_row`, `start`, `stop`, `shutdown`, `store.register`) and nothing else.
- `start` must be idempotent: it runs after the shell is ready and again after every Reload Mods. Work that must survive a reload belongs in a cached service started from `start` and stopped from `shutdown`.
- Preserve existing documents and unknown fields. Do not migrate, delete, or overwrite user presets unless the requested feature requires it.

## Verify and document

- Parse every changed Lua file and validate every changed JSON file before handoff, for example with `npx --yes luaparse <file>`.
- Update `README.md` for user-visible behavior, `ROADMAP.md` for implementation status, and `TEST_PLAN.md` for observable scenarios.
- Do not mark a gameplay checkbox complete from static validation. Mark it only after the user or logs confirm the behavior in Dragonwilds.
- For a crash or hang, inspect both `ue4ss/UE4SS.log` and `%LOCALAPPDATA%\RSDragonwilds\Saved\Logs\RSDragonwilds.log`; a native failure may leave no Lua error.

