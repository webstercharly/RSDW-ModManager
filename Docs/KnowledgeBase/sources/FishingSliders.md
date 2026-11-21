# FishingSliders 1.1.2: implementation guide

Source: `References/OnlineMods/FishingSliders/1.1.2/extracted/FishingSliders/Scripts/main.lua`
(1,538 lines). No licence stated: learn, do not copy.

**What it does:** sliders for the fishing loop (bite wait, fish stamina, junk, catch size, rod penalty,
net odds, spot respawn, rods that never wear, auto-rebait, refill key, AFK fishing).

**Why read it:** the best example of **tuning game data in place**: class default objects, component
templates, data assets and curves, all reversible, plus injecting the game's own input actions.

## Pattern: vanilla-first value writer

```lua
local VAN = {}
local function wantOf(key, cur, fn)
    if VAN[key] == nil then VAN[key] = cur end   -- remember the game's value the first time seen
    if not S.on then return VAN[key] end         -- off: always want the original
    return fn(VAN[key])                          -- on: derive from the original, never from the current
end
-- usage
local want = wantOf("cdo.BiteTimerMin", cur, function(v) return math.max(0.1, v * cfg.BiteWait) end)
if differs(cur, want) then cdo[f] = want; wrote() end    -- differs() uses 1e-4
```

Because every target is computed from the stored original, repeat passes are idempotent and
turning the mod off simply makes `want` equal the original. Keys are unique per target (for example
`"sp.<species>.<field>.<i>"`).

## What gets written, and where

Paths were "read off the shipped containers" (unpacked game assets), loaded with `LoadAsset` (the
`loadObj` helper) and found with `StaticFindObject` (`findObj`):

| Target | Path or access | Fields changed |
|---|---|---|
| Fish controller class default | `/Fishing/Gameplay/Fishing/BP_CatchableFishController.Default__BP_CatchableFishController_C` | `BiteTimerMin`, `BiteTimerMax` (floor 0.1x, 0 means never bites) |
| Combat component **template** | `...BP_CatchableFishController_C:BP_Fishing_Combat_GEN_VARIABLE` | `FishNormalStaminaDrainRate`, `FishWeakStaminaDrainRate` (fish tires), the five `Player*` drain rates (your stamina) |
| Species data assets | `CFSD_*` found through nearby fishing nodes | `Info.ChanceOfJunkWhenUsingPreferredBait` / `...NotUsingPreferredBait` (0..1 clamp); `Info.NormalDrop/PristineDrop.CatchChances[i].FishAmount` (rounded int) |
| Rod level penalty curve | `Curve_Float_FishingRodPowerLevelDifferenceToPlayerStaminaDrainMultiplier` | `FloatCurve.Keys[i].Value` for keys with `Time < 0`, pulled toward 1.0: `1 + (v-1)*slider` |
| Net spell module | `DA_Fishing_Cast_Net:SpellModule_NetFishing_0` | `FishingProbabilityPerLevelDifferences[i]` capped at 1.0 |
| Cast speed curve | `Curve_Float_RodChargeFractionToCastSpeed` | AFK cast tuning |

Notes:
- Default objects are named `Default__<Class>_C`; component templates use the `:<Name>_GEN_VARIABLE` suffix.
- Controllers read these when they spawn at the cast, so changes apply from the **next cast**.
- Species assets are never loaded by the mod. It reaches them through nodes already in the world: "a species
  asset that nothing references gets freed and reloaded, and loading them ourselves every pass made the game do
  exactly that (measured 2026-09-24)".
- TArray access: `arr:GetArrayNum()` with a `#arr` fallback; arrays are 1-indexed in Lua (`CatchChances[i]`);
  loops are capped (16, 40) as a safety limit.
- "Rod species ship an EMPTY `CatchChances` table (always one fish)", so catch size only changes nets.

## Spreading the work (`applyStep`)

A pass is a queue of jobs (`applyController`, `applyPenalty`, `applyNet`, `applySpeciesAll`); each tick runs
at most three, so no frame pays for everything. A pass restarts every 10 s or when settings change (`S.dirty`).
If settings equal the normal game and nothing of ours remains written (`S.touched`), it does no work at all
("with every slider at its default the mod writes nothing").

## Fishing spots

- Spots are `BP_FishingNodeV2_*` actors (class name contains `_Rod_` or `_Net_`). They load about 250-280 m
  out. `FindAllOf` costs about 50 ms, so the list is cached (`nodesCached(pawn, maxAge)`), refreshed on age or travel.
- Each has `node.ResourceRespawnComponent`; `r:GetQuantityAvailable()` gives the quantity.
- **Respawn time** lives per spot at
  `r.SpawnSettings.ResourceRespawnSettings.RespawnTime.RespawnDuration` as `{Days,Hours,Minutes,Seconds}` in game
  time. One in-game day is 24 real minutes, so N real minutes = N game hours: `{D=floor(h/24), H=h%24}`.
  Original per node stored in `S.nodeVan[fullName]`.
- To make an empty spot refill at once: `r:PauseRespawning()` then `r:ResumeRespawning()`.
- A refilled spot may keep a depleted flag that rejects casts. Clear it like the game's own replenish
  ("DevMenu routine, verified 2026-09-23"):
  `n.NodeState.bDepleted = false; n:OnRep_NodeState(n.NodeState); n:UpdateNodeFX()`.
- Manual refill: `r:SetResourceAmount(max)` with `max = n:GetMaxNumberOfAvailableResources()` (10 fallback), then
  the same flag clear.
- **Keep fish in spot** detects a catch by polling: the spot's quantity dropped by one and the player's fishing
  state says "caught a fish" within half a second (or a net catch paid Fishing XP); then it restores
  `q + 1` with a chosen probability. The author says hooks here caused four UE4SS crashes.

## Held tool, bait, wear

- Held tool and inventories are read through the pawn, as in AutoTool. Rod and net durability are topped back to
  full each tick (`wearTick`). Auto-rebait chooses the biggest stack of a different bait (`bestBaitSlot`) and
  equips it.

## AFK fishing: injecting the game's own input

```lua
sub  = FindAllOf("EnhancedInputLocalPlayerSubsystem")[...]
IA   = { prim = LoadAsset IA_PrimaryAction, left = IA_FishingMiniGame_MoveLeft,
         right = IA_FishingMiniGame_MoveRight, reel = IA_Fishing_Reeling }
sub:InjectInputVectorForAction(ia, { X = 1.0, Y = 0.0, Z = 0.0 }, {}, {})   -- every frame
pc:SetControlRotation({ Pitch, Yaw, Roll })                                  -- face the spot
```

The loop reads `pawn.FishingComponent.InternalState` (`CurrentActivity`, `FishingResult`, `CastResult`) and
`FightingFishInternalState.FishSwimmingState` about every 100 ms, and injects the matching action each frame.
The game does the fishing exactly as if keys were held. Stop conditions: objects go away, no fishing component,
three counted misses (the first cast that hits the water is a free retry), timeouts. Fish and aim use
yaw `atan2(dy, dx)` and pitch `atan2(dz, flat)` from the pawn to the node.

## Keys, again

See [reference/stability-rules.md](../reference/stability-rules.md) rule 15. Final design: no `RegisterKeyBind`. A 33 ms
loop (`pollKeys`) reads `pc:IsInputKeyDown(k.key)` for each configured key, fires a flag on the down edge, and the
250 ms main tick does the work. `engineKeyName()` converts config names (`F6`, `A`, `ZERO`, `NUM_ONE`) to engine
key names (`Zero`, `NumPadOne`).

## Co-op and servers

Runs on the host or solo only unless `AllowAsClient`. v1.1.0 added a dedicated-server path (`isDedicated`,
`serverTick`, `serverConfigChanged`): the data sliders run there from the server's own `config.txt`, the per-player
features do not.

## Reusable recipes

| Need | Take this |
|---|---|
| Reversible data tuning | `wantOf` store-original pattern |
| Edit class defaults | `Default__<Class>_C` object, change fields, applies to later spawns |
| Edit a component's defaults | `:..._GEN_VARIABLE` template object |
| Edit a data asset curve or array | index loop with cap, 1-based, `GetArrayNum` |
| Spread cost | job queue, 3 jobs per tick, 10 s cycle |
| Detect events without hooks | compare polled quantity to previous and to a state flag in a half-second window |
| Drive gameplay as if the player did | `EnhancedInputLocalPlayerSubsystem:InjectInputVectorForAction` |
| Aim at an actor | `SetControlRotation` from atan2 |
| Make a world actor refill | pause/resume its respawn component, clear its depleted node state |

## Cautions

- Probes dated 2026-09-23 to 2026-11-04 on the author's build.
- Editing assets other mods also edit will fight: always compute from stored originals, as here.
- Heavy write targets (species assets across all nodes) are only rewritten when a value actually differs.
