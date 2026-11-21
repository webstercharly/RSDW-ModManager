# NoAutoPickup 1.1.0: implementation guide

Source: `References/OnlineMods/NoAutoPickup/1.1.0/extracted/NoAutoPickup/Scripts/main.lua`
(466 lines). No licence stated: learn, do not copy.

**What it does:** stops the game pulling dropped items to the player. Optional exceptions let
enemy loot bags and mined-node drops still fly in.

**Why read it:** the cleanest example of "change one game number, remember the vanilla value,
restore on disable", and of identifying game objects by structure when no flag exists.

## Shape of the file

```text
cfg table -> valid/full helpers -> config.txt parser -> Mod Menu sync -> localPC finder
-> magnet read/write -> loot-bag pull -> gathered-item pull -> apply() -> tick() -> 500 ms game-thread loop
```

## Core mechanism: one number

The player pawn has an `ItemMagnet` component with `MagnetRange` (350 cm in the shipped game).

```lua
local m = pc.Pawn.ItemMagnet
orig[full(m)] = m.MagnetRange          -- read once, before the first write
want = cfg.Enabled and cfg.Range*100 or orig[key]
if math.abs(cur - want) > 0.5 then m.MagnetRange = want end
```

- `orig` is keyed by the magnet's **full name**, so a new character (new object) is read fresh.
- The write is checked by reading back; if it did not stick, it warns once ("a game update?")
  and does nothing further.
- Disabled means writing the stored original back. Nothing is saved to disk.
- The value is re-checked every tick, so it is re-applied if the game resets it.
- Whole-metre slider: `math.floor(r + 0.5)`; NaN is clamped.

## Local player and host

```lua
pc:IsLocalController()                       -- ground truth for "mine"
pc:HasAuthority()                            -- host or solo only; clients get a one-time warning
```

`localPC()` caches the controller, re-validates it each time, and scans with
`FindAllOf("PlayerController")` at most every 3 s (10 s while there is no world). It rejects
names containing `MainMenu` or `Default__`.

## Loot bags (exception 1)

Enemy loot packs still fly in from the game's own range. Mechanism:

1. Match items by **name fragment** (`AlwaysPickup`, default `Pack`, comma-separated,
   lowercase, plain find). `Pack` matches `ITEM_Consumable_GoblinPack`.
2. Once a second: `FindAllOf("RuntimeSpawnedWorldItem")` (0-2 ms for 33 actors).
3. For each: `item = w.ItemData:GetFName():ToString()`; component
   `w.MagneticComponentGrantItem`.
4. Skip if `m:HasTarget()` is true (already flying) or `m.bHasBeenGranted`.
5. Distance gate is the mod's own: farther than the Range setting, no farther than the game's
   recorded range.
6. `m:BP_MagnetizeToPlayer(pawn, true)` pulls it. It is **not** range-gated by the game, so the
   distance check is yours. `HasTarget` flips to true afterwards, so each item is pulled once.

## Gathered items (exception 2, default off)

Hard problem: an item dropped by mining looks exactly like enemy loot (same class, same launch).
The mod separates them by **where it landed**:

1. Every second list all `RuntimeSpawnedWorldItem` actors. The first scan after enabling only
   records what is already lying around.
2. Candidate = new since last scan, full name starts `BP_RuntimeSpawnedWorldItem_C ` (excludes
   `_NoExpiry_` and `_ProcessingStation_` variants), not a loot bag, has the magnetic component with
   `bAutoMagnetizationEnabled`, not granted, not flying, and `LaunchableComponent.bLaunched`.
3. Only if candidates exist: `FindAllOf("ResourceRespawnComponent")` (35-56 ms), take each owner's
   location. Every ore node, tree and plant has one.
4. A candidate within 350 uu of a node becomes `pending`.
5. Pending items are pulled on the **next** scan (about 1 s later, after landing), only if within
   12 m of the player (so another player's node in co-op is ignored).

Measured spacing: enemy loot lands 14-26 uu from its corpse; node drops 21-316 uu from the node.

## What it deliberately avoids

- `ItemDropComponent.ItemsToDrop` and `DropItemFromInventory`: both **crashed** the game in the
  author's probe.
- Any hook. Everything is polling.
- Writing to disk or the save.

## Main loop

```lua
LoopInGameThreadWithDelay(500, function() pcall(mainTick) end)
```

A fallback exists for builds without the game-thread timer: `LoopAsync` that sets a `queued` flag and
hands work to `ExecuteInGameThread` so only one is outstanding and a stuck one clears after 5 s.
The comment says why: `LoopAsync` callbacks run on a second thread without UE4SS's lock.

## Mod Menu keep-in-step rule

The author's comment: the `MM_LIVE` list, `cfg`, `config.txt` and `modmenu.json` must all agree,
because a key missing from `MM_LIVE` is "a setting that silently does nothing". Worth adding a
startup check that every manifest key exists in the live list.

## Reusable recipes

| Need | Take this |
|---|---|
| Reversible numeric override | `orig[key]`, read-once, write-back, read-after-write check |
| Local, host-only gating | `IsLocalController` plus `HasAuthority` |
| Identify spawned objects without a flag | Structural tests: class-name prefix, state flags, proximity to a known marker component |
| Costly scan only when needed | Run the expensive `FindAllOf` only if a cheap pass found a candidate |
| Delayed action to let physics settle | Queue as pending, act on the next scan |
| Self-diagnosing after game updates | Warn once when a field is missing or a write does not stick |

## Cautions

- All measurements dated 2026-10-01 to 2026-10-20 on the author's build.
- `BP_MagnetizeToPlayer` and the component field names are exact strings. If a game update renames
  one the mod does nothing by design, so add the read-back warning pattern to our own uses.
