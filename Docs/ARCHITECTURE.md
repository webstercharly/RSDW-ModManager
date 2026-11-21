# Architecture

## Goals

1. Provide a cleaner in-game interface that is safe to leave installed during normal play.
2. Host independent, drop-in modules without the shell knowing what any of them do.
3. Use the game's normal inventory and server RPC paths for multiplayer compatibility.
4. Keep user data versioned, recoverable and outside update-owned files.
5. Make game-version compatibility failures visible and non-destructive.

## Non-goals

- Replacing unrelated game-mod tooling.
- Requiring a server-side mod.
- Continuously scanning every UMG inventory widget.
- Depending on, loading or writing another mod's files.

## Runtime boundaries

```text
Mod Manager (this repository)
├── bootstrap and compatibility checks
├── engine adapter
│   ├── local player/controller discovery
│   ├── inventory/equipment discovery
│   └── guarded reflected calls
├── shared services
│   ├── game-thread scheduler (rlm_async)
│   ├── equipment mutation lock (rlm_transaction)
│   └── persistence (versioned JSON, atomic writes, rolling backups)
├── module host
│   ├── folder scan of Modules/
│   ├── manifest validation
│   └── start / stop / shutdown lifecycle
└── UI
    ├── pause-menu entry and F7
    ├── module rail and shared module screen
    └── transient status notifications

Modules/<Name>/            (each is its own repository)
├── manifest.json
├── module.lua
└── services and assets the module owns
```

## Shell files

All Lua modules use an `rlm_` prefix to prevent collisions with other UE4SS mods.

| File | Responsibility |
|---|---|
| `main.lua` | Minimal UE4SS entry point and protected bootstrap. |
| `rlm_bootstrap.lua` | Lifecycle and service wiring. |
| `rlm_paths.lua` | Installed-mod and update-safe user-data paths. |
| `rlm_config.lua` | Static mod configuration from `config.txt`. |
| `rlm_json.lua` | Private dependency-free JSON codec. |
| `rlm_log.lua` | Log helper. |
| `rlm_store.lua` | Documents: shell settings plus module-registered documents, atomic writes, backups. |
| `rlm_modules.lua` | Folder-scan discovery, manifest validation, runtime loading and lifecycle. |
| `rlm_engine.lua` | Reflected Dragonwilds object discovery and guarded calls. |
| `rlm_inventory.lua` | Equipment/inventory snapshots and item matching. |
| `rlm_async.lua` | Shared game-thread scheduler. |
| `rlm_transaction.lua` | Shared lock so equipment changes never overlap. |
| `rlm_ui.lua` | Pause-menu integration and screen lifecycle. |

## Module boundary

The host knows only the manifest schema. Visible module names, menu labels,
descriptions and primary-action text come from each module's manifest.
Behaviour is returned by that module's own `module.lua`. A module is any folder
under `Modules/` with a valid manifest; one invalid module is skipped (and
logged) without affecting the others. An empty `Modules/` folder is valid.

Lifecycle, in order:

1. The shell loads each module's `module.lua`, which registers any documents it
   owns and loads its services.
2. After the UI is ready the host calls `start(state)` on each module that has
   one. Reload Mods loads the new runtimes, calls `stop()` on the old ones, then
   calls `start(state)` on the new ones, so `start` must be idempotent.
3. When the manager unloads, each module gets `shutdown()` then `stop()`.

Services that must survive a reload (for example a key poller) are started from
`start`, kept in a cached `require`d table, and stopped from `shutdown`.

## Data ownership

Installed files are read-only program assets. Mutable data belongs under
`%LOCALAPPDATA%\RSDWLoadoutManager`:

```text
RSDWLoadoutManager/
├── settings.json          (shell)
├── <module documents>     (registered by modules, e.g. gear-swaps.json)
├── migration.json
├── logs/
└── backups/
    └── <kind>-YYYYMMDD-HHMMSS.json
```

Every document contains `schemaVersion`, `modVersion`, and `updatedUtc`.
Unknown fields are preserved when possible so a downgrade does not silently
destroy newer settings.

## UI performance rules

- No permanent `FindAllOf` loop.
- No inventory widget enumeration during normal play.
- Refresh only on screen open, explicit selection, inventory-change event, or user request.
- Cache widget references only while the owning screen is alive.
- Restore altered widget colours when the screen closes.
- Limit each game-thread slice and move non-engine data work off critical callbacks.

## Compatibility policy

The engine adapter owns all game-specific class, field and method names. A
future game update should generally require changes in that module rather than
throughout the UI and services. Startup probes report one of:

- `ready`: all required paths found;
- `degraded`: browsing works but applying is disabled;
- `incompatible`: the mod stays loaded but performs no equipment mutations.
