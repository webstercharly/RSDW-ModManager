# Test plan

## Status convention

- `ROADMAP.md` records implementation completion.
- This file records observed live behaviour; a box is checked only after the
  scenario has passed in Dragonwilds.
- Static syntax/schema validation does not count as a live gameplay pass.
- Each module repository has its own test plan.

## Current validation status

- [x] Lua files pass parser validation.
- [x] Manifest and settings JSON files pass syntax validation.
- [x] Mocked (non-game) checks: module folder scan, ordering, invalid and unsafe folders skipped, empty `Modules/`, start/stop/shutdown order, module-registered documents across a simulated reload.
- [ ] Everything below, in Dragonwilds.

## Safety gates

- Syntax-check every Lua file before live loading.
- Validate every JSON document against its schema version.
- Never mutate equipment when preflight cannot identify the local inventory.
- Never issue an automatic rollback batch after a failed equipment change.

## Module host

- [ ] With no modules installed the manager opens, says no modules are installed, and RELOAD MODS works.
- [ ] Copy a module folder into `Modules/`, press RELOAD MODS, and it appears without editing any file.
- [ ] Delete a module folder, press RELOAD MODS, and it disappears with no errors in `UE4SS.log`.
- [ ] A folder with an invalid manifest is skipped and logged; other modules still load.
- [ ] Modules appear in manifest `order`.
- [ ] Reload Mods with a module that has background work leaves exactly one running copy of that work.
- [ ] Closing the game or unloading the mod runs each module's shutdown and logs no errors.

## Persistence

- Fresh install creates default documents without reading or writing another mod.
- A module that registers a document gets its own file under `%LOCALAPPDATA%\RSDWLoadoutManager`.
- Interrupted writes retain the previous valid document.
- Backups rotate without deleting the newest valid copy.
- Unknown fields survive a read/write round trip.
- Updating installed mod files does not alter `%LOCALAPPDATA%` data.

## Standalone boundary

- Start successfully when no other gameplay utility mod is installed.
- Never scan another mod's directories or IPC documents.
- Preserve user documents across an installed-mod update.

## UI

- Mouse and keyboard navigation; controller navigation is intentionally out of scope.
- Open and close repeatedly from the pause menu.
- Close during selection and during a queued transaction.
- No duplicate pause-menu button after map/world reload.
- Readable status without depending on colour alone.
- Reload confirmation appears in the global header without replacing module details.
- Showing and hiding the reload notification does not move the module list or Reload Mods button.
- Entry list fills available height while the input and actions remain bottom-aligned.
- Long names wrap visibly without clipping later detail lines.
- Esc closes the manager while normal content or the text field has focus.
- Reload Mods refreshes manifests and module runtimes without invoking
  `RestartCurrentMod`, retains one panel, and allows continued play.

## Multiplayer

- Client-only mod joining a remote server.
- Host-owned server without a server-side installation.
- Server rejection and correction are reported accurately.
