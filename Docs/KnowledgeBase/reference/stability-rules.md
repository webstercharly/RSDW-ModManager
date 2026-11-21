# Stability rules

Every rule below comes from a crash the original authors hit. Native crashes
inside UE4SS or the engine are not catchable with `pcall`, so these rules are
about not making the call at all.

## Object handles

1. **A freed object can crash `IsValid()` itself.** After a world closes, its
   objects are freed. Calling `IsValid` on a stored pointer to one crashed the
   game natively.
   - Slayer (`main.lua` ~3700): after Exit to Main Menu and re-entry, pressing a
     key near an NPC crashed. Fix: on world change, drop every stored object the
     old world created.
   - MapMarkers (`main.lua` ~172): keeping `MapCustomizationComponent` handles
     crashed 3 of 3 runs (`UE4SS.dll +0x2AC8D7`) because front-end player
     controllers are freed at world load. Fix: store nothing, do the one write in
     the construction callback.
   - *Measured.*
   - **Apply:** never cache a UObject across a world change. Re-find it each time,
     or clear caches on the load-map hook.
   - Our own dump of 2026-11-16 15:14 is a null read at `UE4SS.dll +0x2ac4b3`, within about 0x424 bytes of the `+0x2AC8D7` MapMarkers recorded for this crash class (see [ue4ss reference](ue4ss.md)).

2. **Calling a method on a null object field crashes.** `IsValid()` first, always.
   ResourceAtlas lost several runs to a crop with no "Dead" mesh; its fix is
   `U.Name(o)` which checks `IsValid` before `GetFName` (`util.lua`). AutoTool
   states the same rule after four probe crashes. *Measured.*

3. **Do not read every property of an object.** ResourceAtlas `game.lua`: a
   probe that read every property of a fishing spot crashed. Read named fields
   only.

4. **Soft references crash when read.** AurelianUI (`main.lua` ~1958, ~2559) and
   ResourceAtlas (`fish.lua` ~45) both hit this. Do not read `TSoftObjectPtr`
   style fields or map values keyed or valued by them. Load textures by full path
   with `LoadAsset` on the game thread instead. *Measured.*

5. **Material functions only exist on dynamic instances.**
   `K2_GetTextureParameterValue` and similar crashed when called on a plain
   material (AurelianUI `minimap.lua` ~828, ~1242). Check the object's class is
   `MaterialInstanceDynamic` first. *Measured.*

6. **Never ask every image in a widget tree for its texture.** AurelianUI 1.5.1
   crashed on the map's shadow-frame image. Ask only the specific named images.

7. **A name reused under the same outer crashes `StaticConstructObject`.**
   ResourceAtlas (`util.lua`) appends a counter to every constructed object name.

8. **An item with an empty data struct can crash the game's own tile code.**
   Slayer `skilltile.lua` ~140: it clones a real tile as a template instead.

## Hooks

9. **Prefer no `RegisterHook` at all where polling works.** FishingSliders took
   four UE4SS crashes from fishing hooks and fight samplers and now has none.
   AutoTool has none either. Slayer and SkillPets keep to a small number of hooks
   that only record a name or set a flag.
10. **A hook callback records; a game-thread tick works.** Slayer's rule: every
    hook callback only appends to a queue. SkillPets: its single hook "only
    compares a name and sets a flag". *Observed in code, repeated across mods.*
11. **Do not hook UI clicks if controller support matters.** MapMarkers: a pad
    does not fire button-click hooks, so it polls input instead.
12. **Do not call `ItemsToDrop` or `DropItemFromInventory` to probe items.**
    NoAutoPickup crashed on both. It identifies node drops by checking for a
    `ResourceRespawnComponent` owner within 350 uu instead.

## Threads and timers

13. **Everything on the game thread.** Starfall: UE4SS `LoopAsync` runs Lua on a
    second thread, and Lua there while a hook fires on the game thread crashed.
    Use `LoopInGameThreadWithDelay` or `ExecuteInGameThread`.
14. **Do not start a UE4SS timer from inside a timer callback.** Starfall: the
    game-thread timer list moves under the walker and crashes. It runs exactly one
    UE4SS timer (a "pump") and drives its own task list from that. See
    [guides/execution-model.md](../guides/execution-model.md).
15. **`RegisterKeyBind` callbacks run on the key thread.** FishingSliders
    (`keythread-6`, 2026-11-04): even a callback that only set a flag crashed the
    game under key spam (4 of 4 runs, 0 of 2 with every key-bind mod off). It polls
    keys on the game thread via the player controller instead. Other mods here
    (AutoTool, Slayer, SkillPets, ResourceAtlas) still use `RegisterKeyBind` with
    flag-only callbacks, so this is a single mod's finding. Treat key spam as a
    test case for our hotkeys. *Measured by one author; unverified here.*

## Timing and load

16. **Wait after the world comes up before scanning.** SkillPets and AurelianUI
    wait several seconds; MapMarkers waits 20 s (`BOOT_GRACE`) before any
    `FindAllOf`. ResourceAtlas found its wait was not the true cause of its crash
    but kept a small margin and gates on `bIsRegistered`.
17. **`FindAllOf` walks every object.** Throttle it (ResourceAtlas scans every
    5 s; MapMarkers does one when the map opens, about 6 ms for 110 components).
18. **No `LoadAsset` before the world has settled** (FishingSliders).
19. **Do not rebuild widgets repeatedly.** Slayer: rebuilding widgets crashed
    UE4SS in Collection Log. Build once per world, then show, hide and rewrite.

## Memory

20. **Out-params leak a registry reference per call.** SkillPets documents that
    UE4SS build `f6d5f942` takes a Lua registry reference for every table passed as
    a non-const OUT param of a UFunction call and never releases it. A per-frame
    trace or overlap call grows memory for the whole session. Its workaround
    (RegSweep) clears marked tables from `debug.getregistry()` outside UFunction
    calls. *Measured by the author on our build; see [guides/performance.md](../guides/performance.md) for the code outline.*

## Data safety

21. **Never write the game's save.** NoAutoPickup, MapMarkers, Slayer, SkillPets
    all keep their own files beside the saves, never inside them. Mods that must
    change save-resident data say so loudly (MapMarkers' over-99-pins warning).
22. **Write files atomically.** Starfall `persist.lua`: temp file, then rename,
    with `.tmp` recovery and `.corrupt` quarantine. Slayer: a purchase whose point
    deduction was not written could be repeated after a crash, so write before
    granting.
23. **Store vanilla values on first read and scale from those.** FishingSliders
    never compounds a change; turning the mod off writes the stored values back.
    NoAutoPickup restores the game's own `MagnetRange` when disabled.

## Logging as a crash tool

24. **Log each step of risky first-time scans.** ResourceAtlas `farm.lua` logs
    every step of its first two scans so a native crash leaves the last call made
    in the log. AurelianUI keeps the previous launch's report file so it survives
    a crash.
