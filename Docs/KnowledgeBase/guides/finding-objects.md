# Guide: finding, validating and holding game objects

**Use this when** you need a reference to a controller, pawn, component, widget, asset or class.

## The calls

| Call | Returns | Cost and notes |
|---|---|---|
| `FindFirstOf("ShortClass")` | first live instance | walks the object array, **35-60 ms**; may return the `/Game` archetype |
| `FindAllOf("ShortClass")` | list of **non-default** instances, **including derived classes**; `nil` if none | **47-60 ms** each; the docs say it excludes default objects, yet mods still met `Default__` names and template or archetype copies, so keep the filters below |
| `StaticFindObject("/Script/Engine.Default__GameplayStatics")` | a loaded object or class by full path | cheap; nil if not loaded |
| `LoadAsset(package)` then `StaticFindObject(package.."."..name)` | an asset not yet loaded | do it on the game thread, not before the world settles |
| `StaticFindObject(pkg.."."..asset.."_C")` | a Blueprint class | load the package first |
| `pawn:GetComponentByClass(cls)` | a component | cheap; `cls` from `StaticFindObject("/Script/Dominion.X")` cached |
| `pc.BP_Components_Inventory`, `pc.ProgressComponent`, `pawn.ItemMagnet`... | components as properties | cheapest |
| `NotifyOnNewObject` | objects as they are created | for screens and one-off objects ([hooks-and-events](hooks-and-events.md)) |
| `AssetRegistryHelpers:GetAsset({PackageName, PackagePath, AssetName})` | pak assets | names are `FName`s |
| `AssetRegistry:GetAssetsByClass({...})` | asset list | cache `name -> package` (RSDWTools) |

`FindAllOf` returns derived classes: `FindAllOf("JournalEntryData")` is already the whole catalog (CollectionLog nearly double counted 1,315 entries as 2,630).

## Filtering out the wrong copies

```lua
local n = full(o)
if n:find("Default__", 1, true) then skip end                       -- class default object
if n:find(":WidgetTree.", 1, true) then skip end                    -- template copy inside a widget blueprint
live = n:find("/Engine/Transient", 1, true)                          -- the real runtime instance
```

AurelianUI `live_root` keeps only `/Engine/Transient`; Slayer's `usable` does the same for screens ("`FindFirstOf` would give the `/Game` archetype").

## The local player

Several mods copy this almost verbatim:

```lua
local function localPC()
  if valid(cachedPC) and cachedPC:IsLocalController() then return cachedPC end
  cachedPC = nil
  if os.clock() < nextScan then return nil end; nextScan = os.clock() + 3      -- throttle the scan
  for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
    local n = full(pc)
    if valid(pc) and pc:IsLocalController() and not n:find("MainMenu",1,true) and not n:find("Default__",1,true) then
      cachedPC = pc; return pc
    end
  end
end
```

- **Use `IsLocalController()`.** `IsPlayerControlled()` is true for any human-driven pawn, and a loop using it returned another player's controller (RSDWTools). `UEHelpers.GetPlayerController()` does not check it.
- Reject names with `MainMenu`: front-end controllers exist before a world does.
- Pawn: `pc.Pawn`; confirm it is on foot with `pawn:GetClass():GetFName():ToString():find("PlayerCharacter")` (AutoTool).
- Character name: `pc.PlayerState:GetPlayerName():ToString()`.
- World: `pc:GetWorld()`; `UEHelpers.GetWorld()` falls back to the game instance.

## Validity rules (these prevent native crashes)

```lua
local function valid(o)
  if not o then return false end
  local ok, v = pcall(function() return o:IsValid() end)
  return ok and v == true
end
```

1. **Check `IsValid()` immediately before every use**, not just when you stored it. AutoTool: the interaction target "can hold a dead handle, and a call on one is a native crash pcall cannot catch (four probe crashes)".
2. **Never call methods on an empty object field**, even `GetFName()` (ResourceAtlas: a crop with no "Dead" mesh crashed repeatedly). Wrap: `U.Name(o)` checks `IsValid` first.
3. **`IsValid()` on freed memory can itself crash.** After a world closes, objects are freed. Do not hold handles across a world change; drop them without touching them ([execution-model](execution-model.md) rule 5). MapMarkers stores **nothing** from `NotifyOnNewObject` for this reason.
4. **Re-resolve, do not cache, objects that can be rebuilt.** EnemyHPNumbers refreshes `rec.char` and `rec.comp` on every scan: "the component can be rebuilt while the actor lives".
5. Cache **classes and default objects** (`StaticFindObject` results) freely; they do not die with a world. Re-check `valid()` anyway.
6. Identify objects by `GetFullName()` or `GetAddress()`, not by Lua table identity. **Measured on our build (1135), 2026-11-20:** `==` between two wrappers of the same UObject is **false**, and a function that returns an object (`GetPawn`, a property read) gives a **new wrapper every call**. Our Mod Manager's No Item Weight cheat tested `stored_pawn == current_pawn`, which never matched, so it removed and re-added a gameplay effect every second (and logged a weak-pointer warning each time). Pointer-based `__eq` only arrived upstream at build 1151. Use a helper: `a == b` first, then `pcall(a:GetAddress() == b:GetAddress())` with `IsValid()` guards.

## Make lookups cheap

- Scan on a long interval (EnemyHPNumbers 3 s min 2 s; ResourceAtlas 5 s), after a cheap trigger (map opened), or after the player moves (AutoTool rebuilds its node list after 8 m or 20 s).
- Do **one** `FindAllOf` for many new items, after the loop (EnemyHPNumbers resolves all new species in one pass).
- Run an expensive scan only when a cheap pass found a candidate (NoAutoPickup runs `FindAllOf("ResourceRespawnComponent")` only when there are new drops).
- Cache lists by key (`classKey -> data`) so one lookup serves every instance.
- Back off after misses: EnemyHPNumbers retries the HUD subsystem every 3 s, then every 30 s after 5 misses.
- A retried failure should not stall each tick: `nextCatalogTry = os.clock() + 10` (CollectionLog).
- Large catalogs: build once, pcall'd, not during the world-load stall.

## Common classes and what they are for

Full list in [reference/game-api-catalogue.md](../reference/game-api-catalogue.md). Quick reference: `PlayerController`, `GameInstance`, `GameStateBase`, `PersistenceSubsystem`, `HUDUISubsystem`, `MapUIAPI`, `MapIconComponent`, `QuestData`, `ItemData`, `FarmSlotComponent`, `ResourceRespawnComponent`, `RuntimeSpawnedWorldItem`, `AiHealthBarComponent`, `EnhancedInputLocalPlayerSubsystem`, `WBP_DominionMinimap_C`, `WBP_TopNav_Map_C`, `WBP_PauseMenuScreen_C`.

## Seen in

[sources/AutoTool.md](../sources/AutoTool.md), [sources/NoAutoPickup.md](../sources/NoAutoPickup.md), [sources/EnemyHPNumbers.md](../sources/EnemyHPNumbers.md), [sources/CollectionLog.md](../sources/CollectionLog.md), [sources/MapMarkers.md](../sources/MapMarkers.md).
