# Guide: performance budget

**Use this when** a feature scans, draws many things, or runs often. Numbers are measurements by the mod authors on the game thread.

## Costs

| Operation | Cost | Source |
|---|---|---|
| `FindAllOf` / `FindFirstOf` | **35-60 ms** (47 ms typical) | EnemyHPNumbers, QuestLog, AutoTool |
| `FindAllOf("MapIconComponent")` | about 6 ms for 110 components | MapMarkers |
| `FindAllOf("RuntimeSpawnedWorldItem")` | 0-2 ms for 33 actors | NoAutoPickup |
| `FindAllOf("ResourceRespawnComponent")` | 35-56 ms | NoAutoPickup |
| Reading all 59 quest states | about 1 ms | QuestLog |
| `HasPickedUpItem` over the catalog | about 0.06 s | CollectionLog |
| 3,356 unlock checks | 20-40 ms | CollectionLog |
| Building the whole catalog | several `FindAllOf` plus about 5,000 objects of work | CollectionLog |
| One float read per tracked enemy | negligible | EnemyHPNumbers |
| Per-icon cost on a minimap | **a ticking widget each, shown or hidden** | ResourceAtlas |
| Polling wheel binding | under 0.1% CPU at 16 ms, gated | RSDWTools |

A frame at 60 fps is about 16 ms: one `FindAllOf` is three frames.

## Rules

1. **Never `FindAllOf` per tick.** Use an interval (2-5 s), a trigger (map opened, key pressed, player moved 8 m), or a cache.
2. **One sweep for many items**, after the loop.
3. **Cheap detector, expensive follow-up**: poll one value, call the costly API only when it changes (EnemyHPNumbers: fill float gates the attribute reads).
4. **Cache per class**, not per instance (affinities).
5. **Time-slice** big walks from a persistent index: N items per tick (CollectionLog 250 groups every 30 s, `HasPickedUpItem` in slices).
6. **Queue jobs** and run at most three per tick (FishingSliders).
7. **Do nothing when nothing is needed**: if settings are vanilla and nothing of yours is written, return early (FishingSliders `S.touched`).
8. **Run work only while visible**: a 20 ms input sampler only while the map is open; polling loops only when a binding exists; scanning inventory widgets only in selection mode.
9. **Back off after failure**: retry at most every 10 s, and slow down further after repeated misses (30 s).
10. **Do not do heavy first-time work during world load**: wait a readiness time ([execution-model](execution-model.md)).
11. **Pool widgets and actors**, cap pool sizes, spare ones `SetVisibility(1)`. Hidden still costs for map icons.
12. **Compare before writing**; write only changed values.
13. **Reuse tables** in hot loops (RSDWTools grab loop mutates pre-allocated tables to keep GC out of the hot path).
14. **Float math for squared distances**: integer squares overflow 32-bit Lua in some harnesses; multiply by `1.0`.
15. **Throttle text updates**: tooltips at most once a minute; text only if it differs from last shown.

## The registry leak (out parameters)

**Measured on our installed build (1135), 2026-11-20: 1.99 registry slots leaked per call with two out tables (300 calls: 11 to 609 slots, +63 KB Lua memory after GC). Fixed upstream at build 1164 (#1452).** A 20 Hz loop with one out table leaks about 72,000 slots an hour. If we move to a loader at or past 1164, this section is unnecessary. Until then:

On build f6d5f942 every table passed as a non-const out parameter of a UFunction call takes a Lua registry reference that is never released (SkillPets, reading `LuaUObject.cpp call_ufunction_from_lua`). Per-frame traces, `K2_SetActorLocation*`, overlaps and attribute reads grow memory for the whole session.

Mitigation (SkillPets "RegSweep"):

```lua
-- mark: remember the tables you pass (weak keys, so marking keeps nothing alive)
local marked = setmetatable({}, { __mode = "k" })
function mark(t) marked[t] = true; return t end
-- sweep: from the main loop only, never inside a UFunction call, at most 4 times a second
local reg = debug.getregistry()
for k, v in pairs(reg) do
  if type(k) == "number" and k > 3 and type(v) == "table" and marked[v] then reg[k] = nil end
end
```

Use `mark({})` for each out param. Provide a kill switch (a file `nosweep.txt` in the mod folder or the shared variable `RegSweep.off`). Only worth adding if you measure growth from per-frame out-param calls.

## Measure it

- Time with `os.clock()` around any new scan; log the first few results (CollectionLog logs "catalog built in %.2f s").
- Count tracked objects per tick and cap them (`MaxTracked`).
- Log memory-affecting counters in a report file.

## Pitfalls

- Per-node map icons.
- A scan inside a hook callback.
- Rebuilding the catalog on every failure.
- Re-applying decorations every tick instead of on a settings generation change (`DECO.gen`, `DECO.budget`).

## Seen in

[sources/EnemyHPNumbers.md](../sources/EnemyHPNumbers.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/CollectionLog.md](../sources/CollectionLog.md), [sources/SkillPets.md](../sources/SkillPets.md), [sources/FishingSliders.md](../sources/FishingSliders.md).
