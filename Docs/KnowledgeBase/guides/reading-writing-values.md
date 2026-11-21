# Guide: reading and writing properties, calling functions, handling UE4SS value types

**Use this when** you touch fields, arrays, maps, structs, text or function results on a game object.

## Properties and calls

```lua
local hp  = comp.MaxNumberOfPins                 -- read a property
comp.MaxNumberOfPins = 1000                      -- write a property
local ok, v = pcall(function() return obj:GetQuantityAvailable() end)   -- call a UFunction as a method
```

Wrap **every** read, write and call in `pcall`. A missing field raises; a changed game build renames fields silently. Read back after writing and warn once if it did not stick (NoAutoPickup: "MagnetRange could not be changed (a game update?); the mod does nothing").

Rules that came from crashes:
- Read **named fields only**. A probe that read every property of a fishing spot crashed (ResourceAtlas).
- Never read a **soft object reference** ([below](#soft-references)).
- Only call functions that exist on the object's real class: material parameter functions exist on `MaterialInstanceDynamic` only (AurelianUI crash). Check `cname(res) == "MaterialInstanceDynamic"` first.
- A function that hung the game thread when called from Lua: `MapUIAPI:ClearPin`, `SetHoveredMapIcon` + `TryRemoveHoveredMapIcon` (MapMarkers, 2 of 2). Call new functions on a test world first.

## Struct, enum and colour values

| Type | In Lua |
|---|---|
| FVector / FRotator | table: `{X=,Y=,Z=}` / `{Pitch=,Yaw=,Roll=}` |
| FTransform | `{Rotation={X=0,Y=0,Z=0,W=1}, Translation={X=,Y=,Z=}, Scale3D={X=1,Y=1,Z=1}}` |
| FLinearColor | `{R=,G=,B=,A=}` in **linear** light |
| Slate colour | `{SpecifiedColor = linearColor, ColorUseRule = 0}` |
| Enum | number (`EUINavigation` 0 Left 1 Right 2 Up 3 Down; `ESlateVisibility` 0 Visible, 1 Collapsed, 2 Hidden, 3 HitTestInvisible, 4 SelfHitTestInvisible) |
| FGameplayTag | `{TagName = FName("...")}` |
| FName / FText / FString | `FName("x")`, `FText("x")`; read with `:ToString()` |
| FHitResult etc. | passed as a table; results come back in tables |

sRGB to linear for colours: `c <= 0.04045 and c/12.92 or ((c+0.055)/1.055)^2.4` (ResourceAtlas). Using sRGB values directly looks washed out.

## Arrays (TArray)

```lua
local n = arr:GetArrayNum()            -- or #arr
for i = 1, n do local el = arr[i] end  -- 1-based
arr:ForEach(function(i, el) local x = el:get() end)
arr[#arr+1] = FName("tag")             -- append (Starfall: actor.Tags)
```

- Cap your loops (RA caps at 16 or 40). A property that is not an array raises.
- Official `TArray` methods: `Empty()`, `GetArrayMax()`, `ForEach(function(i, elem) ... end)` with `elem:get()` / `elem:set(v)`; **return `true` from the callback to stop early**. Assignment `arr[i] = v` works.
- Official `TMap` methods: `Find(key)` (**throws** if absent), `Add(key, value)` (replaces), `Contains(key)`, `Remove(key)`, `Empty()`, `#map`, `ForEach(function(k, v) ... end)` (early break the same way). Guard `Find` with `Contains` or `pcall`.
- Struct arrays: `arr[i].Field = v` writes in place (FishingSliders curves and catch tables).
- Falling back: `pcall(function() n = a:GetArrayNum() end); if type(n) ~= "number" then pcall(function() n = #a end) end`.

## Maps (TMap)

```lua
map:ForEach(function(k, v)
  local key = k:get().TagName:ToString()
  local val = v:get()                              -- enum number
end)
```

Used for `DamageTypeAffinities` (EnemyHPNumbers). Read keys and values only when their types are plain (enum, object, struct of plain fields).

## Out parameters

```lua
local out = {}
lib:BP_TryGetFloatAttributeValue(char, attrClass, -1.0, out, {})
local found = out.OutbFound; local value = out.OutAttributeValue
```

- Pass an empty table for each out parameter.
- **All out values land in the first table**, named with the parameter names (confirmed on our build 2026-11-20: `GetViewportSize(a, b)` put `SizeX` and `SizeY` in `a`, nothing in `b`). Reading `OutbFound` from the second table gives nil. Accept either: `v = outA.X; if v == nil then v = outB.X end` (EnemyHPNumbers, measured).
- Some calls return values in extra return values instead (AurelianUI `uv()` checks the tables then the returns).
- **Each out-table call leaks a registry reference** on our build (1135). Called every frame, memory grows. Mark and sweep (SkillPets RegSweep, [performance](performance.md)). Upstream fixed this at build 1164 (#1452), and fixed corruption of following params for non-struct out params at 1163 (#1454): out-param layout may change on a newer loader, so re-test any code that reads out tables.
- Assigning a **weak-object property** from Lua is unsupported on our build (`[push_weakobjectproperty] Operation::Set is not supported` in `UE4SS.log`); upstream added the setter at build 1151. Do not rely on such a write succeeding; read it back.
- Out tables of trace calls: hit data is under `out.OutHit` (`ImpactPoint`, `Location`).

## Text

- `FText("...")` to set, `tb:GetText():ToString()` to read. Compare `textOf(tb) == s` to confirm a write.
- Names: `o:GetFName():ToString()`, full path `o:GetFullName()` is `"Class /Path.Object"`; strip the class with `match("^%S+%s+(.+)$")`.
- Display names often need cleaning from internal names (`ITEM_Armour_T2_Body_Linen`); data tables or `GetDisplayName` give the real text.

## Userdata that is not an object

UE4SS returns many things as `userdata`, but only some are UObjects. FText, FName, FString, native structs and soft/lazy references are userdata too. Calling `:GetClass()` on them is an access violation that `pcall` does not catch.

RSDWTools `safety.lua` classifies by shape:

| Kind | Test | Allowed |
|---|---|---|
| uobject | `pcall(val:GetClass())` returns non-nil | everything |
| text_like | has a `ToString` field, not a uobject | `:ToString()` only |
| soft_ref | has `Get` | `:Get()`, then re-classify |
| tarray | `#val` works | length, iterate |
| unsafe_ud | none of the above | opaque; never traverse |

Probe with `pcall(function() return val:GetClass() end)`: testing for an `IsA` field fails because UE4SS exposes `IsA` through an `__index` function, so it reads nil on valid objects. Probes themselves are wrapped in `pcall` because some userdata raise on a missing field.

A central helper for this belongs in your engine boundary file, so new crash classes are fixed in one place.

## Soft references

**Reading any `SoftObjectProperty` from Lua kills the Lua state on UE4SS build f6d5f942 (our installed build, 1135) and f58e8f84** (RE-UE4SS issue #1433; reproduced by CollectionLog's author 2026-09-23; AurelianUI and ResourceAtlas hit it too).

Status upstream: fixed by PR #1465 (builds 1172-1174) and, for UE 5.6 soft paths (Dragonwilds is 5.6), by #1486 (builds 1190 and 1213). The staged `1217-r2` should contain both if its number tracks upstream's; **unverified in game**. Until a loader is proven, keep avoiding soft reads ([reference/ue4ss.md](../reference/ue4ss.md)).

What to do:
1. Never read icon or mesh or texture soft properties (`Icon`, `DisplayIcon`, `SpellIcon`, `SpellTagIcon`).
2. Generate a table offline on a build that can read them: `"<objectPath>|<property>" -> "<assetPath>"` (CollectionLog `softpaths.lua`).
3. At runtime look up the path and load by full path: `StaticFindObject(path)`, else `LoadAsset(path)` then retry.
4. A missing entry means no picture, never a crash.
5. Alternatively list the paths by hand (ResourceAtlas `fish.lua`).

Also avoid map values or keys that are soft references (AurelianUI `main.lua` ~2559 reads maps only "when its key and value types are plain").

## Writing safely

- Store the vanilla value the first time, write relative to it, restore on disable ([tuning-game-data](tuning-game-data.md)).
- Do not write a value every tick if it already equals the target: compare first (`differs(a, b)` with 1e-4).
- Write to **template and default objects** to change future spawns, to instances to change live ones.
- Never write to the character save file.

## Seen in

[sources/EnemyHPNumbers.md](../sources/EnemyHPNumbers.md) (out params, TMap), [sources/FishingSliders.md](../sources/FishingSliders.md) (arrays, curves), [sources/CollectionLog.md](../sources/CollectionLog.md) (soft refs), [sources/RSDWTools.md](../sources/RSDWTools.md) (safety classifier).
