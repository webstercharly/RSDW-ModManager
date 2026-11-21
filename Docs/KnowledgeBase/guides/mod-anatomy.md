# Guide: mod anatomy, loading and packaging

**Use this when** you start a new mod or change how one is laid out, loaded or shipped.

## Folder layout that works

```text
<ModName>/
  enabled.txt            loads the mod (a line in Mods/mods.txt is the alternative)
  Scripts/main.lua       entry point; other files are require()d or loadfile()d relative to Scripts/
  config.txt             user settings, key = value
  modmenu.json           Mod Menu manifest (or modmenu.txt)
  README.txt             install, use, settings, what removal does
  LICENSE.txt            if you want others to reuse it
  art/  data/            optional: PNGs, generated tables
  dlls/ Native/          optional: native code
```

- **Loading:** a folder with `enabled.txt` runs even if it is not in `mods.txt` (QuestLog, CollectionLog, EnemyHPNumbers and our mod load this way).
- **Each mod has its own Lua state.** Globals are private to the mod. Use `ModRef:SetSharedVariable/GetSharedVariable` to talk to other mods ([persistence-and-config](persistence-and-config.md)).
- **Reload:** loader hot reload is off here (`EnableHotReloadSystem = 0`). Mods that need reload build it themselves ([execution-model](execution-model.md)).
- Prefix your module and global names (`rlm_`) so mods cannot collide.

## Finding your own folder

Every mod does this at the top:

```lua
local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local dir = src:match("^(.*)[/\\][^/\\]*$")          -- the Scripts folder
local root = dir:match("^(.*)[/\\][^/\\]*$")         -- the mod folder
```

RuneSchema also normalises slashes and matches `^(.*)/[Ss]cripts/main%.lua$`; if that fails it logs a fatal line and stops instead of guessing.

## Loading your own files

| Need | How | Seen in |
|---|---|---|
| A code module | `require("name")` (searches `Scripts/`) | Starfall, ResourceAtlas, SkillPets |
| Optional code | `pcall(require, "looks")`; skip if missing or erroring | SkillPets, ResourceAtlas `LoadPart` |
| A data table | `loadfile(root.."\\Scripts\\data.lua")` then `pcall(chunk)`, expect a table | Slayer, CollectionLog |
| Large generated data | same, generated offline (CollectionLog `softpaths.lua`, 4,660 lines) | CollectionLog |
| Fresh code on reload | add a `package.searchers[1]` that `loadfile`s your own modules, because UE4SS keeps compiled files in memory | Starfall |
| Native code | `package.loadlib(dll, "Export")` | Class Specialisations |

Lua allows 200 locals per function, and large mains hit it. Split into files or tables of functions.

Note: `require` returns only the module under UE4SS (Lua 5.4 normally also returns loader data). Take one value.

## Structure that scales

Starfall's layout is the cleanest example of keeping risky code isolated:

- `core/`: pure logic, **no engine calls**, testable outside the game.
- `game/`: the only layer that touches UObjects.
- `art/`, `lib/`: data and helpers.
- `ss.lua`: one runtime file (log, guarded calls, timers, hook trampolines, reload) that is safe to run twice.

Other patterns: ResourceAtlas loads each feature as a **part** inside `pcall` and disables a part after 3 consecutive failures; Slayer splits a 4,000-line main into data files and feature files returning tables; our own `rlm_*.lua` services with thin `Modules/<Name>/module.lua` adapters.

## Guarded entry

```lua
local errors = 0
local function mainTick()
  local ok, err = pcall(tick)
  if not ok then errors = errors + 1; if errors <= 3 then log("tick error: "..tostring(err)) end end
end
```

Log the first few errors only, so a failing tick cannot flood the log.

## Config (`config.txt`)

Parse `Key = value`, `#` comments, trailing `# ...` comments stripped. Type the value from the default in your `cfg` table (boolean words `true/1/yes/on`), clamp numbers, ignore unknown keys with a log line. With every setting at default the mod should write nothing. See [persistence-and-config](persistence-and-config.md).

## Dev builds versus release

Starfall gates dev tooling: `dev/harness.lua` loads only if `dev_enabled.txt` exists, and release packages omit `dev/`. Probe and debug commands then cannot run in a release even if the flag file is present.

## Packaging checklist

- `enabled.txt` present; `config.txt` and `modmenu.json` beside `Scripts/`.
- README: install path, use, settings, **what removal does** ("nothing is saved to your character"), warnings where removal is not clean (MapMarkers over 99 pins).
- Zip layout: a single `<ModName>/` folder, or game-root paths if you ship paks (`RSDragonwilds/Binaries/Win64/ue4ss/Mods/...` and `Content/Paks/~mods/...`). Say which in the README.
- CurseForge-style hosts reject `.png` in a mod zip: ship images as bytes in a Lua module and write them out on first use ([ui-construction](ui-construction.md)).
- Keep credits (AurelianUI credits Relic Hunter UI). Include the licence text if you reuse MIT code.
- Keep a version history in the README; AurelianUI's per-version fix list is the most useful document in the library.

## Seen in

Starfall (layout, dev gating), ResourceAtlas (parts), Slayer (data files), SkillPets (optional hooks table, pak packaging), RuneSchema (path discovery, plugin manifests), all Lua mods (config and `enabled.txt`). Details: [sources/Starfall.md](../sources/Starfall.md), [sources/RuneSchema-and-ModMenu.md](../sources/RuneSchema-and-ModMenu.md).
