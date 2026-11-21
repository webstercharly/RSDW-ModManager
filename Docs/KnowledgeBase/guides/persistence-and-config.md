# Guide: saving data, config files, Mod Menu and talking to other mods

**Use this when** a mod stores anything, reads settings, shows settings in Mod Menu, or cooperates with another mod.

## Where to store things

| Data | Location | Why |
|---|---|---|
| Per-character progress, looks, records | `%LOCALAPPDATA%\RSDragonwilds\Saved\<Mod>-<name>[-<guid8>].txt/json` | beside the game's saves, survives mod updates; **never inside the game's save** (Slayer, MapMarkers, CollectionLog, SkillPets, AurelianUI per world) |
| Our own manager data | `%LOCALAPPDATA%\RSDWLoadoutManager` | update-safe |
| Settings | `config.txt` in the mod folder | user-editable |
| Generated reports and caches | the mod folder | diagnostics, saved class path |
| Embedded art or data | Lua modules | hosts reject some file types |

Mod-folder storage is lost or overwritten on reinstall (RSDWTools keeps `ipc/` there): avoid for user data.

**Never write the game's save.** Reading it offline as text is fine ([reading-game-state](reading-game-state.md)).

Fallback if `LOCALAPPDATA` is missing: use the mod folder.

## File names

`safeName(n) = n:gsub("[^%w%-_]", "_")`. Key per-character files by name plus the save's `char_guid` (first 8 chars): a new character can reuse a deleted one's name. Non-ASCII names add a hash suffix. Per-world files add a world key.

## Atomic writes (Starfall `core/persist.lua`, MIT; MapMarkers does the same)

```lua
write(path..".tmp", data)               -- 1. temp file in full
os.remove(path); os.rename(tmp, path)   -- 2. replace
-- load: if path is missing try path..".tmp" (a crash between remove and rename leaves a complete temp file)
-- if decode fails: rename to path..".corrupt", report, start fresh
```

Inject the file functions (`read`, `write`, `rename`, `remove`) so tests need no disk. Debounce saves (MapMarkers writes one second after the last change); save after every meaningful event for important data (Starfall).

**Write the cost before the reward.** Slayer: "a purchase whose point deduction was not written could be repeated after a crash". Keep a `.bak` (CollectionLog reads `.bak` if the main file is missing).

Append-only text is a simple durable record (CollectionLog lines `E <pid> <time>`; the first sweep records existing unlocks as "before the log").

## Formats and bounds

- Tab-separated text for small tables (`x<TAB>y<TAB>icon<TAB>color`).
- JSON for structured records; ship a decoder (`lib/json.lua`) and share it with any mod that reads your files.
- **Bound every read.** Class Specialisations reads at most 64 KB (read 65,537 bytes and reject if over); CollectionLog's Slayer reader caps at 1 MB; reject unknown keys; all-or-nothing parse.
- Version your files: a `V` line or a `schema` number.

## `config.txt`

```text
# comment
Enabled = true
WorkKey = U              # trailing comment
Range = 0
```

Parse `^([%w_]+)%s*=%s*(.*)$`, strip `%s*[#;].*$`, type the value from the default (boolean `true/1/yes/on`, number, string), **clamp**, ignore unknown keys with a log line, NaN becomes the default.

## Mod Menu

A separate mod reads your manifest and publishes settings through shared variables. Exact rules from RuneSchema's adapter:

**Manifest** `modmenu.json` (or `modmenu.txt`): `schema: 1`, `id` (`[%w_-]+`), `name` (40), `author` (40), `version` (20), `description` (300), `minModMenu`, `runsOn`, `config {file, format}`, `settings[]` (max 1024).

| Setting `type` | Fields |
|---|---|
| `header` | `label`, `collapsed` |
| `toggle` | `key`, `default` |
| `slider` (alias `number`) | `key`, `min` < `max`, `step`, `decimals`, `suffix`, `default` |
| `choice` | `key`, `options` (up to 50), `default` |
| `key` | `key`, `default`, `context` (`world`, `chest`, `build`, `menus`, `anywhere`), `keyNames: "unreal"` |
| `text` | `key`, `maxLength` (1-200), `default` |
| `button` | `action`, `label` |
| any | `label` (80), `tooltip` (300), `restart`, `runsOn` (`yours`, `host`, `server`, `both`), `showIf {key, is}`, `valueLabels` |

Keys are `[%w_.-]+` and unique. `runsOn` host/server settings are refused unless the local player has host authority.

**Runtime protocol** (shared variables):

| Variable | Meaning |
|---|---|
| `ModMenu.<id>.<key>` | current value of each setting |
| `ModMenu.<id>.rev` | revision; reapply only when it changes |
| `ModMenu.<id>.action` | `"<action>#<n>"` from button presses |
| `ModMenu.request.set` | you to the menu: `"<id>#<unique>\|<Key>=<value>"` |
| `ModMenu.health.<id>` | `"off"` or `"unknown"` |
| `ModMenu.version` | menu version |

```lua
local function shared(key) local ok, v = pcall(function() return ModRef:GetSharedVariable("ModMenu."..ID.."."..key) end) return ok and v or nil end
local rev = shared("rev")
if type(rev) == "number" and rev ~= last then
  last = rev
  for _, k in ipairs(MM_LIVE) do local v = shared(k); if v ~= nil and type(v) == type(cfg[k]) then cfg[k] = v end end
  clampCfg()
end
local act = shared("action")                                       -- first read just records the baseline
if act ~= lastAct then lastAct = act; pending = tostring(act):match("^([^#]+)") end
```

- **Keep four lists in step:** `cfg`, `config.txt`, `modmenu.json`, and `MM_LIVE`. A key missing from `MM_LIVE` is "a setting that silently does nothing" (NoAutoPickup, AutoTool). Add a startup check.
- Keys and other restart-only settings cannot apply live: log and tell the player ("works after a game restart").
- Status line back to the menu: `ModRef:SetSharedVariable("ModMenu.request.set", ID.."#"..os.time().."-"..n.."|Status="..text)`.
- The `lua` config format means the menu edits a Lua-literal file; values that are not plain literals are locked.

## Talking to other mods

- **Shared variables:** `ModRef:SetSharedVariable(name, value)`. Allowed types (official docs): `nil`, `string`, `number`, `bool`, `UObject`, `lightuserdata`. They **survive hot reload** (not reset) and **any mod can overwrite any variable**, so namespace names (`Mod.Key`) and never share transient objects such as actors; share class defaults only. Namespaces seen: `ModMenu.*`, `PauseDock.owner/rev`, `Slayer.present`, `PetRock.State`, `RegSweep.off`, `EnemyHPNumbers.*`.
- **Read another mod's files, never its Lua** (CollectionLog reads Slayer's JSON): no UObject calls in the reader, no writes to the other mod's files. Version the contract: no `schema` = legacy, `schema 1` full, `schema > 1` with `minReader <= 1` reads known fields, `minReader > 1` shows "update me" and no rows. Bound size, keep the last good read, show a failure note after 3 bad reads.
- **Step aside** for a vanilla feature (Slayer "Retired" mode) or another mod that owns something (SkillPets and Pet Rock).
- **Ownership token** for shared UI (`PauseDock`).
- Publish what you show so others can avoid duplicates (EnemyHPNumbers `EnemyHPNumbers.*`).
- A byte relay over a game Blueprint component exists in RuneSchema (`ServerRequestRuneSchemaAction("mod.data", channel, action, text, revision)`; chunked, CRC-checked, replay-protected) but needs its pak on the server.

## Pitfalls

- Writing user data into the mod folder.
- Reading or writing the game save.
- Unbounded reads of files other programs can edit.
- Applying Mod Menu values every tick instead of on `rev` change.
- Not clamping config numbers.

## Seen in

[sources/MapMarkers.md](../sources/MapMarkers.md), [sources/Starfall.md](../sources/Starfall.md), [sources/CollectionLog.md](../sources/CollectionLog.md), [sources/RuneSchema-and-ModMenu.md](../sources/RuneSchema-and-ModMenu.md), [sources/Slayer.md](../sources/Slayer.md).
