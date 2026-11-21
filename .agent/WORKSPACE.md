# Workspace map

## Paths

Paths are relative to the UE4SS `Mods` folder of the Dragonwilds install
(`RSDragonwilds/Binaries/Win64/ue4ss/Mods`).

- Project root (edit here): `RSDWLoadoutManager`
- Installed modules: `RSDWLoadoutManager/Modules/<Name>` (separate repositories)
- UE4SS runtime log: `ue4ss/UE4SS.log`
- Dragonwilds runtime log: `%LOCALAPPDATA%/RSDragonwilds/Saved/Logs/RSDragonwilds.log`
- Update-safe user data: `%LOCALAPPDATA%/RSDWLoadoutManager`

## Source layout

- `.agent/SKILLS.md`: project-local skill index. Load required skills before work.
- `.agent/skills/`: canonical portable copies of project-specific agent skills.
- `Docs/KnowledgeBase/`: task-organised developer knowledge for UE4SS and
  Dragonwilds mods (`guides/`, `reference/`, `sources/`). Entered through
  `.agent/skills/rsdw-mod-development/SKILL.md`; its `README.md` also holds the
  licence table for reusing reference code.
- `Scripts/main.lua`: protected mod bootstrap.
- `Scripts/rlm_bootstrap.lua`: lifecycle and service wiring.
- `Scripts/rlm_ui.lua`: persistent Mod Manager shell, pause-menu entry and F7.
- `Scripts/rlm_modules.lua`: folder-scan module discovery, lifecycle and safe in-process reload.
- `Scripts/rlm_engine.lua`: reflected Dragonwilds object/component boundary.
- `Scripts/rlm_inventory.lua`, `rlm_transaction.lua`, `rlm_async.lua`: shared equipment and scheduling services.
- `Scripts/rlm_store.lua`, `rlm_json.lua`, `rlm_paths.lua`, `rlm_config.lua`, `rlm_log.lua`: standalone persistence and config.
- `Modules/<Name>/manifest.json`: module identity, version, order and menu metadata.
- `Modules/<Name>/module.lua`: thin view/action adapter plus the module's own services and assets.
- `Docs/ROADMAP.md`: implemented versus outstanding work.
- `Docs/TEST_PLAN.md`: observable live tests; do not infer passes from syntax checks.

## Published modules

1. `RSDW-ModManager-HotSwap` installs as `Modules/HotSwap`.
2. `RSDW-ModManager-Map` installs as `Modules/Map`.

Inspect each manifest rather than hardcoding menu labels.

## Reload boundary

- A change to a module runtime or manifest can normally use the in-menu
  **Reload Mods** action.
- A change to the persistent host shell/bootstrap, especially `rlm_ui.lua`,
  `rlm_modules.lua`, `rlm_bootstrap.lua` or `main.lua`, requires a normal
  Dragonwilds restart.
- Never call `RestartCurrentMod` from a callback or tick.

## Validation commands

Run from the project root:

```powershell
npx --yes luaparse Scripts\changed_file.lua | Out-Null
Get-Content Modules\ChangedModule\manifest.json -Raw | ConvertFrom-Json | Out-Null
```

For a crash or hang, inspect both runtime logs listed above. A native crash may
leave no Lua error.
