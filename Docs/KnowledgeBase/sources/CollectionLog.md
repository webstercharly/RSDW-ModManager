# CollectionLog 2.2: implementation guide

Source: `ue4ss/Mods/CollectionLog/Scripts/` (`main.lua` 4,058 lines, `softpaths.lua` 4,660 lines of generated data, `slayerlink.lua` 565 lines), read in
place (installed, not in `References/`). Author Maxxfilth. No licence file: learn, do not copy.

**What it does:** an Old School RuneScape style collection log: every item held, creature killed, recipe, building piece, spell and journal page, with game art,
grayed out until obtained. Opened from the pause menu. Read-only towards the game.

**Why read it:** it holds the **most important UE4SS finding in the library** (soft references crash this UE4SS build), plus patterns for **cataloguing
the game's data**, **time-sliced scanning**, **per-character records**, and **loosely coupling two mods**.

## The soft-reference crash (read this first)

From `main.lua` ~672 and the header of `softpaths.lua`:

> Reading any `SoftObjectProperty` from Lua crashes UE4SS builds **gf6d5f942** (the Nexus "latest") and **f58e8f84** (RE-UE4SS issue **#1433**; reproduced
> here 2026-09-23 on both, the first soft read kills the Lua state).

- Our installed UE4SS is **commit f6d5f942** (see `References/README.md`), so this applies to us. Other mods report the same (AurelianUI, ResourceAtlas).
- The author's fix is a **precomputed lookup table**: `Scripts/softpaths.lua` maps `"<object path>|<property>"` to `"<asset path>"` for every icon and picture the
  mod needs. It was **generated offline by a command script (`data/cmd/dumpsoft.lua`) run on "stable UE4SS 0196ef29"**, which does not crash.
- At runtime: `softPath(o, prop)` takes the object's full name without the class prefix, looks up `SOFT[path.."|"..prop]`, returns `""` if missing ("a missing entry
  means no picture, never a crash"). Textures are then loaded by full path with `LoadAsset`/`StaticFindObject`.
- The lookup table is loaded with `loadfile(root.."\\Scripts\\softpaths.lua")` under `pcall`.
- **Observation about our references:** the archive in `References/UE4SS/Candidates/3.0.1-946-g265115c/` is named `UE4SS (latest)-4-3-0-1-0196ef29-...`, i.e. build
  `0196ef29`. Our README calls it older than our installed loader and says not to install it. Collection Log's author calls `0196ef29` "stable" for soft
  references. These two statements pull in different directions and need a decision before anyone swaps loaders. Not tested here.

## Cataloguing the game's data (`buildCatalog`)

Type to query to unlock test (all verified in game 2026-09-18, each sweep under 50 ms):

| Tab | `FindAllOf` class | Count | "Is it done?" call |
|---|---|---|---|
| Items | `ItemData` | filtered | `pc.ProgressComponent:HasPickedUpItem(obj)` |
| Recipes | `RecipeData` | 1,218 | `prog:IsRecipeUnlocked(o)` |
| Buildings | `BuildingPieceData` | 856 | `prog:IsBuildingUnlocked(o)` |
| Spells | `DominionSpellData` | 95 | `prog:IsSpellUnlocked(o)` |
| Journal | `JournalEntryData` | 1,315 | `JournalFunctionLibrary:IsJournalEntryUnlocked(o, pc)` |
| Enemies | the character save (`KilledOnceAIs`) | | read offline |

- **`FindAllOf` returns derived classes**, so each base query is the whole catalog. Also scanning `RuneRecipeData`, `UtilitySpellData` or the `JournalEntry*`
  subclasses double counts (journal looked like 2,630 and is really 1,315).
- Spells: `DominionSpellData` also holds internal combat definitions for weapons and NPC attacks ("Combo 01", "Bucket", "Abyssalwhip"). Only entries with
  `SpellDisplayName` are player spells (about 39, not 80). A `realNameOnly` flag drops unnamed entries.
- Same-name objects (the same beam in four tiers) are de-duplicated by display name, and `FindAllOf` order is **not stable**, so sort by a stable key.
- The catalog build runs several `FindAllOf` (about 50 ms each) and thousands of objects of work: it is `pcall`'d, retried at most every 10 s, and not run during
  the world-load stall (`S.readyAt` = 15 s after entering) unless the player opens the panel (`force`).
- `pc.ProgressComponent` may not exist yet, or ever, on some co-op clients: treat `nil` as "try later".

## Time-sliced scanning

- `HasPickedUpItem` over every item takes about 0.06 s, so `scanPickups(pc, count, ...)` walks the list in slices from a persistent `S.scanIndex`.
- The live sets (3,356 checks in 20-40 ms) run in one go when the panel opens, and in the background in slices of `LIVE_SLICE = 250` groups every `LIVE_EVERY = 30` s.
- Backpack, worn gear and personal storage are also watched once a second: `pc.BP_Components_Inventory`, `BP_Components_Loadout`, `BP_Components_PersonalInventory`, reading
  `inv:GetItemFromSlot(i)`.

## Reading the character save offline

Kills come from the character's save file, **read-only as text**: `text:match('"KilledOnceAIs"%s*:%s*%[(.-)%]')`, then `for pid in list:gmatch('"([^"]+)"')`. A table
`ENEMIES[pid] -> display name` was built from the game's creature data and name tables. Also reads `"char_guid"` from the save to key per-character files. The
character name comes from `pc.PlayerState:GetPlayerName():ToString()`. If the save is missing (a co-op client), the Enemies tab says so.

## Per-character record

`%LOCALAPPDATA%\RSDragonwilds\Saved\CollectionLog-<name>-<guid8>.txt` (append-only lines such as `E <pid> <time>`, a `V` version line), next to the game's saves so mod updates
keep it. Non-ASCII names get a hash suffix (`nameHash`). The first sweep on a character records all existing unlocks as "before the log". Ownership changes (`ownerKey = pcName.."|"..name`)
trigger `dropWorld()`.

## Pad window with a fixed pool

Controller support (2.2.0) reuses the QuestLog recipe ([QuestLog.md](QuestLog.md) sections 3-5). Extra rule: **never build more than `PAGE_MAX = 40` game button cells per page**
("game buttons per cell are the 512-row crash profile"). The window shows entries a page at a time from a **fixed pool**, restyled per page, never rebuilt. A list uses `LIST_ROWS` x 2 cells,
a grid `GRID_ROWS` x columns, capped at `PAGE_MAX`. The mouse window (built once per world, kept hidden) is untouched while the pad window is used.

## Pause entry and click hook

Same shared block as QuestLog: `NotifyOnNewObject(PauseMenuScreen)` store, game-styled button, `RegisterHook("/Script/CommonUI.CommonButtonBase:HandleButtonClicked", ...)` records names.

## Loose coupling with another mod (`slayerlink.lua`)

- Reads the other mod's **files**, not its Lua: `Saved\Slayer-<key>.json` (same key as its own record), optional `Saved\Slayer-catalog.json`, and the read-only shared variable
  `Slayer.present`. Never writes a Slayer file, never touches its Lua state, **no UObject calls in the file at all** (pure Lua).
- **Contract versioning** in the JSON: no `schema` = legacy; `schema 1` full; `schema > 1` with `minReader <= 1` reads known fields and ignores the rest; `minReader > 1` shows one
  note ("update Collection Log") and no rows.
- Defensive reading: `MAX_BYTES = 1 MB` (real files are 5-30 KB), keeps the last good read on unreadable text, after 3 failures the tab says so, `.bak` fallback and `MISS_LIMIT = 2`
  before declaring "no file". It carries **its own copy of the JSON decoder** "so both sides read the same text the same way".
- Without the file, the tab does not exist and the rest works as before; `loadfile` under `pcall`.
- A late drop is announced only if newer than 10 minutes (`TOAST_WINDOW = 600`), older unseen drops are recorded quietly.

## Reusable recipes

| Need | Take this |
|---|---|
| Soft-reference icons without crashing | offline-generated `object|property -> path` table, `loadfile` at runtime |
| Whole-game catalogs | `FindAllOf` base class, de-dupe by name and stable sort, filter by display-name field |
| Unlock and progress queries | the `Progress` component calls in the table above |
| Heavy per-item calls | slices from a persistent index, N per tick |
| Persist progress per character | append-only text next to the game saves, key by name plus `char_guid` |
| Integrate with another mod | read its files and a `present` shared variable; version the contract with `schema` and `minReader` |
| Big lists in game buttons | fixed pool, page, restyle; never one widget per row |

## Cautions

- The catalog numbers come from game 1.0 (2026-09-18) and will change with updates.
- The soft-path table must be regenerated for new game versions, on a UE4SS build that can read soft references.
