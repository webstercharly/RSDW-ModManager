# RSDW Mod Manager

A standalone in-game mod hub for RuneScape: Dragonwilds, built on UE4SS. It adds
a `MOD MANAGER` screen to the pause menu (or `F7`) and hosts **drop-in modules**.
The manager itself has no gameplay features. Each module lives in its own
repository and is installed by copying one folder.

PC-only, keyboard and mouse. It does not inspect, load or write files owned by
another mod.

## Modules

| Module | Repository | What it does |
|---|---|---|
| Hot Swap | `RSDW-ModManager-HotSwap` | Colour-coded combat equipment swaps with configurable hotkeys. |
| Map | `RSDW-ModManager-Map` | Native in-game minimap, OSRS-style HUD orbs, chest and lore markers, Nearby Destinations. |
| MCP | `RSDW-ModManager-MCP` | Public read-only local diagnostics and loaded-world observation for MCP clients. |

## Install

1. Install [UE4SS](https://github.com/UE4SS/RE-UE4SS) for Dragonwilds.
2. Copy this repository's contents into
   `RSDragonwilds/Binaries/Win64/ue4ss/Mods/RSDWModManager/`
   so that `Scripts/main.lua` sits directly inside that folder.
3. Copy each module's folder (for example `Modules/HotSwap`) into
   `RSDWModManager/Modules/`.
4. Start the game. Open the manager with `Esc > MOD MANAGER` or `F7`.

To add or remove a module later, copy or delete its folder and press
**RELOAD MODS** in the manager. There is no index to edit.

User data (settings, swaps, backups, logs) is stored in
`%LOCALAPPDATA%\RSDWModManager\`, so updating or reinstalling the mod never
replaces it.

## Writing a module

A module is a folder under `Modules/` containing:

- `manifest.json`: `schemaVersion` (1), `id`, `name`, `description`, `version`,
  `order`, `entry` (normally `module.lua`) and `ui.menuLabel` plus optional
  `ui.actions` (`id`, `label`, `inputHint`, `requiresInput`, `destructive`).
- `module.lua`: returns a table. `activate(state)` is required and returns
  `{ status, detail, rows }`. Optional: `run_action`, `select_row`,
  `rename_selection`, `start(state)`, `stop()`, `shutdown()`.
- Any services and assets the module needs, beside those two files. Add the
  module folder to `package.path` at the top of `module.lua` (see the Hot Swap
  module for the short pattern). Use an `rlm_` prefix on service names.

Lifecycle:

- `start(state)` runs once the shell is ready and again after every Reload Mods,
  so it must be idempotent.
- `stop()` runs when a reload replaces the module and when the manager unloads.
- `shutdown()` runs only when the manager unloads. Put work that must survive a
  reload (key pollers, schedulers) behind `start` and clean it up here.
- A module that needs saved data calls
  `require("rlm_store").register(kind, { file, base, validate })` and then uses
  `store.get(kind)` and `store.save(kind)`. Files are written atomically with
  up to 12 numbered backups per document under the user-data folder. Updates
preserve existing dated backups.

Shared services available to modules: `rlm_engine` (guarded Dragonwilds object
access), `rlm_inventory` (equipment and inventory snapshots), `rlm_async`
(game-thread scheduler), `rlm_transaction` (equipment mutation lock),
`rlm_store`, `rlm_log`, `rlm_ui` (`report_status`, `is_open`).

## Development

Parse Lua with `npx luaparse <file>`. See `AGENTS.md` for the agent workflow,
`Docs/ARCHITECTURE.md` for the design, and `Docs/KnowledgeBase/` for UE4SS and
Dragonwilds developer notes. `Docs/REPOSITORY_POLICY.md` defines which module
capabilities are public and which remain private.

## Licence

MIT. See `LICENSE`. Game assets, textures and text belong to Jagex.
