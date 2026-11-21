# Implementation roadmap

## Phase 0 — standalone foundation

- [x] Create a self-contained UE4SS mod.
- [x] Record architecture, UI and testing plans.
- [x] Create an independent module namespace.
- [x] Add a protected UE4SS bootstrap.
- [x] Add standalone `config.txt` and Mod Menu metadata.
- [x] Confirm the scaffold loads in the live UE4SS log.

## Phase 1 — persistence

- [x] Private JSON codec.
- [x] Update-safe `%LOCALAPPDATA%` storage foundation.
- [x] Atomic replacement with a recoverable previous document.
- [x] Versioned settings schema and module-registered documents.
- [x] Timestamped rolling backup rotation.

## Phase 2 — engine and inventory layer

- [x] Local controller, pawn and inventory discovery.
- [x] Equipment snapshot capture.
- [x] Stable item identity and quantity matching.
- [x] Startup compatibility probe and degraded mode.

## Phase 3 — in-game interface

- [x] Pause-menu `MOD MANAGER` entry and F7 shortcut foundation.
- [x] Isolated module manifests and runtime entry points.
- [x] Manifest-driven menu labels and primary action text.
- [x] Initial native-styled status shell.
- [x] Scrollable module navigation suitable for 10-20+ modules.
- [x] Dark high-contrast text input styling.
- [x] In-menu UE4SS reload with unload cleanup.
- [x] Replace unsafe UE4SS self-restart with in-process manifest/module refresh.
- [x] Separate global reload notifications from module status and instructions.
- [x] Keep global notifications inside a fixed header row without layout movement.
- [x] Anchor module controls to the bottom with a fill-height entry list.
- [x] Auto-size wrapped module details instead of clipping them at a fixed height.
- [x] PC-only keyboard-and-mouse scope; controller navigation intentionally excluded.
- [ ] Settings, export and backup management.

## Phase 4 — drop-in modules

- [x] Discover modules by scanning `Modules/` (no central index).
- [x] Module lifecycle: `start`, `stop`, `shutdown`.
- [x] Module-registered persistent documents.
- [x] Empty `Modules/` folder is valid and explained in the panel.
- [x] Split Hot Swap and Map into their own repositories.
- [ ] Live-validate discovery, Reload Mods start/stop ordering and shutdown with both modules installed.
- [ ] Optional manifest `minManagerVersion` check.

## Phase 5 — release

- [ ] Run the complete test plan.
- [ ] Package a recoverable release archive.
- [ ] Document install, update and uninstall procedures.
