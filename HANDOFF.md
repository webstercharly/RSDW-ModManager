# Cross-tool handoff

## Public shell navigation and in-process UI reload (26 November 2026)

- Vendored UI Kit `dd98250` and added the compact/destination row treatment,
  inline detail actions, per-view action labels and deterministic action-dock
  placement used by the public modules.
- The shared read-only inventory adapter now exposes stable equipment-slot
  labels and a character-bound backpack gear picker for Hot Swap. It rechecks
  the selected item immediately before saving a preset slot and performs no
  equipment mutation.
- **Reload Mods** now debounces duplicate requests, replaces `rlm_ui.lua` and
  the shared presentation modules in process, cancels the old delayed loops,
  restores the open module and calls an optional idempotent `on_host_reload`.
  The public shell contains no module-specific service or HUD names.
- `main.lua`, `rlm_bootstrap.lua` and `rlm_modules.lua` still require a normal
  restart. Static validation is required below; live public-package validation
  remains unchecked in `Docs/TEST_PLAN.md`.

## Graphite UI Kit integration in 0.1.2-dev

- The public shell uses the shared kit for detail cards, hover effects,
  pinned navigation and pagination. The gallery exercises the bundled
  theme and illustration path. Drop-in modules own their services and
  start through the public module lifecycle.
- The public package still needs its installed-game test plan.

## Bounded backups in 0.1.1-dev

- The storage writer rotates 12 numbered backups per registered document.
  It preserves earlier dated backups and uses the same atomic save path for
  both shell and module-owned documents.
- An integrated live capture spent 4.335 s in the old backup directory listing.
  The public shell now avoids the shell process and records phases on slow
  saves. Gameplay verification of this public layout is pending after restart.

- Lua syntax and three storage regression tests passed, including a registered module document.

## Public/private repository boundary

- `RSDW-ModManager-MCP` is the new public read-only diagnostics module. The
  manager README lists it beside Hot Swap and Map.
- Game-writing MCP capabilities belong in private `RSDW-ModManager-Automation`,
  with a separate server/mailbox. The public MCP and shell do not load it.
- `Docs/REPOSITORY_POLICY.md` records the same visibility rule for the remaining
  module families, including mixed modules that need splitting.
- Static documentation change only; installation and live module validation are
  tracked in the MCP repository.

## Baseline (Mod Manager 0.1.0-dev, drop-in module host)

- Active objective: live validation of the module host with the two published
  modules, Hot Swap (`RSDW-ModManager-HotSwap`) and Map (`RSDW-ModManager-Map`).
  Nothing in `Docs/TEST_PLAN.md` is checked yet.
- Exact next step: install the manager, copy `Modules/HotSwap` and `Modules/Map`
  into `Modules/`, start the game, open the manager, and work through the
  "Module host" section of `Docs/TEST_PLAN.md` and each module's own plan.
  Record observed results in this file.

### What the shell does

- `rlm_modules.lua` scans `Modules/` for folders with a valid `manifest.json`
  (fallback: optional `Modules/index.json`). Empty is valid.
- Runtime contract: `activate` required; optional `run_action`, `select_row`,
  `rename_selection`, `start(state)`, `stop()`, `shutdown()`. `start` runs after
  the UI is ready and again after Reload Mods, so modules keep it idempotent.
  `shutdown` runs only on manager unload.
- `rlm_store.register(kind, spec)` lets a module own a document in user data.
  The shell itself only owns `settings.json`.
- Shared services: `rlm_engine`, `rlm_inventory`, `rlm_async`, `rlm_transaction`,
  `rlm_store`, `rlm_log`, `rlm_ui`.

### Static validation done

- Every Lua file parses (luaparse, Lua 5.3 grammar) in the combined install
  (shell plus both modules). Every `require("rlm_*")` target resolves, and every
  texture the Map module names exists in its `art/` folder.
- Mocked tests (fengari Lua with stubbed `io`): module scan and ordering,
  invalid and unsafe folders skipped, empty `Modules/`, start/stop/shutdown
  order, `store.register` across a simulated reload, and rejection of an unsafe
  document file name.

### Live results

- None recorded. Static checks prove syntax and logic against stubs only.

### Risks and assumptions

- Module discovery uses `io.popen("dir /b /ad ...")`, the same mechanism the
  backup rotation already uses. If it is unavailable the host falls back to
  `Modules/index.json`, which the repository does not ship.
- Hot Swap's key poller and swap service now start from the module's `start`
  hook instead of the shell bootstrap. The order matches the old one (after the
  UI) but has not been run in game.
- A change to `rlm_ui.lua`, `rlm_modules.lua`, `rlm_bootstrap.lua` or `main.lua`
  needs a normal game restart, not Reload Mods.
