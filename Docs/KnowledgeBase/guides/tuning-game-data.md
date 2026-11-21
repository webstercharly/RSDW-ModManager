# Guide: changing game values safely (tuning data, defaults and limits)

**Use this when** a mod changes numbers the game owns: ranges, timers, drain rates, drop tables, respawn times, caps.

## The pattern: vanilla-first, relative, reversible

```lua
local VAN = {}
local function wantOf(key, cur, fn)
  if VAN[key] == nil then VAN[key] = cur end     -- remember the game's value the first time
  if not S.on then return VAN[key] end           -- off: the original
  return fn(VAN[key])                            -- on: derive from the original, never from the current value
end
local want = wantOf("cdo.BiteTimerMin", cur, function(v) return math.max(0.1, v * cfg.BiteWait) end)
if math.abs(cur - want) > 1e-4 then obj[field] = want end
```

- Repeat passes are idempotent; settings can change live; disabling restores originals.
- Key each target uniquely (`"sp.<species>.<field>.<i>"`).
- With every setting at default the mod writes **nothing** (FishingSliders, NoAutoPickup).
- Read back after a write; warn once if it did not stick, then do nothing further.
- Clamp so the game cannot be bricked: bite wait floor 0.1x because 0 means "never bites".
- Single numbers keyed by object full name when objects are rebuilt per character (NoAutoPickup: `orig[fullName(magnet)]`).

## Where a value lives decides when it takes effect

| Target | Access | Effect |
|---|---|---|
| Class default object | `StaticFindObject("<pkg>.Default__<Class>_C")` | applies to **future spawns** (fish controller read at the cast: next cast) |
| Component template | `"<pkg>.<Class>_C:<Name>_GEN_VARIABLE"` | every later instance inherits it |
| Data asset / curve | `StaticFindObject(path)` after `LoadAsset(pkg)` | everything that reads it |
| Live instance field | find the instance, write the field | now |
| Per-instance copy of a table | per node, e.g. `r.SpawnSettings.ResourceRespawnSettings.RespawnTime.RespawnDuration` | that node only |

Edit both CDO/template (future) and live instances (now) when you need both.

## Arrays, curves and tables

```lua
for i = 1, math.min(arrLen(a), 16) do a[i] = want(a[i]) end              -- 1-based, capped
c.FloatCurve.Keys[i].Value = ...                                         -- curve keys have .Time and .Value
o.Info.NormalDrop.CatchChances[i].FishAmount = n                         -- struct arrays write in place
```

- An empty table can mean "always one" (rod species ship empty catch tables), so a size multiplier changes nothing there.
- Penalty-style curves: pull keys toward neutral with `1 + (v-1)*slider`.
- Capped probabilities: `math.min(1.0, v * k)`.

## Do not load data you can reach through live objects

FishingSliders reaches species assets through the fishing nodes already in the world. Loading them itself every pass made the game free and reload them ("a species asset that nothing references gets freed and reloaded", measured 2026-09-24).

## Spread the cost

Queue writes as jobs, run at most three per tick, repeat every 10 s; skip the pass entirely when settings are vanilla and nothing of yours is still written (`S.touched`).

## Change gameplay without writing

| Goal | Technique | Seen in |
|---|---|---|
| Stop items flying to the player | `pawn.ItemMagnet.MagnetRange = 0` (350 cm vanilla); pull chosen items yourself with `MagneticComponentGrantItem:BP_MagnetizeToPlayer(pawn, true)` | NoAutoPickup |
| Faster respawn | shorten the per-node duration, then `PauseRespawning()` + `ResumeRespawning()` to make an empty node re-check | FishingSliders |
| Refill a resource node | `r:SetResourceAmount(max)`, `n.NodeState.bDepleted = false`, `n:OnRep_NodeState(n.NodeState)`, `n:UpdateNodeFX()` | FishingSliders |
| Keep a fish in the spot | detect the catch by polling then `SetResourceAmount(q + 1)` | FishingSliders |
| Keep a rod from wearing | top durability up each tick | FishingSliders |
| Unlock every world setting | set each loaded `UDifficultySettingData.PlayerAdjustable = 3` and `bCanBeChangedAfterWorldCreation = true` | RSDWTools |
| Attribute and effect changes | `UDominionGameplayEffectsComponent:InstantiateGameplayEffect` then `ApplyGameplayEffect`, or write `AttributeValues[i]` on `UDominionAttributesComponent` | RSDWTools |
| Skill XP | write `comp.Skills[i].CurrentXP` then call `SkillPerkComponent:HandleSkillLevelIncreased` after a level change | RSDWTools |
| Rename or restyle without a write | return a value from a hook | Starfall |

## Authority and scope

- Run tuning on the **host or solo** only unless there is an opt-in (`AllowAsClient`); check `pc:HasAuthority()`.
- Dedicated server: data sliders run from the server's config, per-player features do not (FishingSliders 1.1.0).
- Mods that edit the same field fight. Computing from stored originals does not stop that; coordinate with a shared variable or document the conflict.

## Pitfalls

- **Observed in play and disassembly (2026-11-20):** The two reflected names
  `domInfiniteSpecialCharge` and `domNoUtilityMagicCooldown` share one thunk
  whose implementation returns immediately. Both logged successful calls while
  the in-game bars still changed normally. The game data exposes a separate
  `Difficulty.Player.SpellCooldownScale` option with a minimum of 0, but
  visibility in the stock world-settings UI and in-game effect are unverified.
- **Static evidence (2026-11-20):** Generated metadata in the installed
  executable includes `LastCastTimeBySpellData` with numeric map values.
  Use the local utility-magic probe to compare timestamp samples. This does
  not establish that changing the map bypasses the cast gate.
- **Observed in play (2026-11-20):** The cast-time probe stopped during class
  property enumeration on the installed loader. The replacement uses the
  documented named reflection lookup and explicit map type check. The
  16:07 live probe recorded the map changing from empty to one timestamp
  after a utility cast. At 16:17 the one-off action changed 228.4602 to
  -86400 with verified readback. The user confirmed an immediate recast.
- **Static evidence (2026-11-20):** The shipped `DecreaseSpecialCharge`
  thunk forwards a float. The implementation flips its sign and forwards it
  to the charge-adjustment path. The experimental action requests exactly
  the missing charge and reads the live meter afterward. Confirmed in play at
  19:42 on 2026-11-20 when the meter changed from 20 to 100.

- Compounding (multiplying the current value each pass).
- Forgetting to restore on disable or removal (the game stays modified until restart).
- Calling `ItemsToDrop` or `DropItemFromInventory` to inspect drops (crashed NoAutoPickup).
- Writing every tick.
- Assuming a field exists: game updates rename them.

## Seen in

[sources/FishingSliders.md](../sources/FishingSliders.md), [sources/NoAutoPickup.md](../sources/NoAutoPickup.md), [sources/RSDWTools.md](../sources/RSDWTools.md), [sources/Starfall.md](../sources/Starfall.md).
