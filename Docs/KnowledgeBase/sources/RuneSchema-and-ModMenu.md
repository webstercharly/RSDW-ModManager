# RuneSchema 0.9.0.1 and the Mod Menu protocol: implementation guide

Source: `References/OnlineMods/RuneSchema/0.9.0.1/extracted/RuneSchema/`: `scripts/*.lua` (1,518 lines in 9 files),
`dlls/` native core and plugins, `Helpy/` (external UI app), `modmenu.json`. Licences are mixed; see its
`Helpy/licenses/` folder (PalSchema MIT, Dear ImGui MIT, nlohmann-json MIT, plus project terms in `LICENSING.md`).
Read those before reusing anything.

**Why read it:** `scripts/helpy-mod-menu.lua` is a complete reader for the **Mod Menu manifest and shared-variable
protocol** that the other mods use, so it documents the exact contract. The rest shows a plugin framework.

## Mod Menu manifest (exact rules from `checkSetting` / `loadSchema`)

File: `modmenu.json` or `modmenu.txt` in the mod folder (`SCHEMA_FILES`, tried in that order).

Top-level fields: `schema` (1), `id` (`[%w_-]+`, else the folder name), `name` (max 40), `author` (40), `version` (20),
`description` (300), `minModMenu`, `runsOn`, `config`, `settings`, optional `"--Helpy"` extension (`schema`, `layout`
`"character"|"settings"`, `tabs` of `{name, keys}` up to 16). Max 1024 settings.

`config`: `{ "file": "settings/settings.ini", "format": "lua" | "json" | (default key=value) }`. For `lua` format, a value that is
not a plain literal is marked `locked` so it cannot be edited from the menu.

Setting types (`TYPES`): `header`, `toggle`, `slider` (alias `number`), `choice`, `key`, `text`, `button`.

| Type | Required | Optional / notes |
|---|---|---|
| all | `type` | `label` (80), `tooltip` (300), `runsOn`, `showIf = { key, is = value or list }` |
| `header` | | `collapsed = true` starts the section folded |
| `button` | `action` (max 60 chars) | no value; menu increments `ModMenu.<id>.action` |
| value types | `key` (`[%w_.-]+`, unique) | `restart` (default from the file's default) |
| `toggle` | | `default` bool |
| `slider` | `min < max` | `step` (default range/100), `decimals`, `suffix` (8), `default` clamped |
| `choice` | `options` list (strings or numbers, up to 50, 40 chars) | `default` must be one of them |
| `key` | | `default` ("none"), `context` in `world, chest, build, menus, anywhere`, `keyNames = "unreal"` to store Unreal key names (Shift, Ctrl, Alt, mouse wheel) |
| `text` | | `maxLength` 1-200 (default 60), `default` |
| toggle, slider, choice | | `valueLabels = { ["<printed value>"] = "word" }` |

`runsOn` values: `yours`, `host`, `server`, `both`. A setting's own value overrides the mod's. In `change()`, a setting whose role is
`host` or `server` is refused unless the local player has host authority ("The host controls this setting").

Colours are validated as `#RRGGBB` (7) or `#RRGGBBAA` (9).

## Shared variable protocol

Names are `ModMenu.<id>.<key>`; every setting's current value is published under its key.

| Variable | Meaning |
|---|---|
| `ModMenu.<id>.<key>` | current value of each setting |
| `ModMenu.<id>.rev` | revision number; increments whenever values change. Mods read the rest only when this changes |
| `ModMenu.<id>.action` | `"<action>#<n>"`; the menu increments `n` for each press. The mod compares to its last-seen value |
| `ModMenu.request.set` | mod to menu write-back: `"<id>#<unique>\|<Key>=<value>"` (MapMarkers' status line) |
| `ModMenu.health.<id>` | `"off"` or `"unknown"` published by the menu |
| `ModMenu.version` | menu's own version, checked against `minModMenu` |

So a consumer is: poll `rev`; on change copy the keys it knows with type checks; poll `action` for buttons.
Read pattern: `ModRef:GetSharedVariable(name)` inside `pcall`.

`validColor`, `luaLiteral`, `stripComment`, `coerce`: values are written back to `key = value` files, JSON, or Lua-literal lines
depending on `format`.

## Plugin framework (RuneSchema)

- **Plugin manifest** `plugin.json`: `SchemaVersion`, `Id`, `Name`, `Version`, `BuiltForRuneSchema`, `EntryPoint` (DLL), `Capabilities`
  (for example `bridge.registry`, `bridge.world`, `presentation.dialogue-cue`, `multiplayer.policy`), `CookedObjects` (paths of pak
  content). Plugin folders hold `dll/` and `paks/<Name>/<Name>_P.{pak,ucas,utoc}`.
- **Bootstrap** `scripts/main.lua`: resolves its own root from `debug.getinfo(1, "S").source` (strip `@`, normalise slashes,
  match `^(.*)/[Ss]cripts/main%.lua$`); loads mappings; then conditionally the Mod Menu adapter and HUD adapter **only if the native
  side registered their entry functions** (`RuneSchemaModMenuExchange`, `RuneSchemaHUDRegister`); then the relay; then logic mods.
  Every `dofile` is in `pcall`.
- **Nested companions:** an enabled RuneSchema mod may carry `mods/<Name>/ue4ss/scripts/main.lua` that RuneSchema hosts, so disabling
  RuneSchema disables every nested script. Names are validated (`valid_mod_name`: not empty, `.`, `..`, no path or control chars).
- **Blueprint "ModActor" loader** (`logicmods-loader.lua`): for each name in a generated list, `AssetRegistryHelpers:GetAsset({PackageName =
  FName("/Game/Mods/<name>/ModActor"), AssetName = FName("ModActor_C")})`, then `world:SpawnActor(actorClass, {}, {})` and call its
  `PreBeginPlay`; `RegisterBeginPlayPostHook` calls `PostBeginPlay` when the actor begins play. `RegisterLoadMapPostHook` resets and
  re-spawns for the new world. `UEHelpers.FindOrAddFName` makes the names. This is how pak-based Blueprint logic mods get started.

## Data relay (client to server to client messaging)

`mod-data-relay.lua` provides a byte channel over a game-owned Blueprint component:

- Endpoint: first `FindAllOf("BPC_RuneSchemaRegistryBridge_C")` whose owner `IsLocallyControlled()`.
- Send: `endpoint:ServerRequestRuneSchemaAction("mod.data", channel, action, text, revision)`.
- Receive: hook `/RuneSchema/Networking/BPC_RuneSchemaRegistryBridge.BPC_RuneSchemaRegistryBridge_C:ClientRuneSchemaNotification`
  (and a matching `...Receipt` hook).
- Packets are JSON text under 4,096 chars: `{bytes, channel, crc, hex, part, sender, sequence, total, v, version}` with 1,024-byte chunks hex
  encoded, CRC32 over the whole payload, **canonical form check** (the received text must equal the re-built canonical string), bounds
  on routes (512), pending (256), incoming budget (16 MB), replay table. Per-sender/channel monotonic sequence number rejects replays;
  30 s deadline per partial message.
- It needs the RuneSchema Networking pak on the server, so it is out of scope for a standalone single-player mod.

## What to take from it

| Need | Take this |
|---|---|
| A compliant Mod Menu manifest | field table above |
| Reading menu values and buttons | shared variable names above |
| Validate untrusted JSON settings | per-field coerce and clamp, collect errors, never throw |
| Locating our own folder | `debug.getinfo(1, "S").source` pattern |
| Gating features on native availability | `type(GlobalFn) == "function"` checks |
| Pak Blueprint loader | `AssetRegistryHelpers:GetAsset` + `SpawnActor` + BeginPlay hook |

## Cautions

- Parts depend on RuneSchema's native DLLs, which are unaudited here.
- The Mod Menu **itself** is a separate mod; this file is RuneSchema's adapter for it. Check actual Mod Menu docs before assuming extra
  setting types.
