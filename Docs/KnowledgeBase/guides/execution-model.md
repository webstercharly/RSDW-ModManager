# Guide: execution model, loops, timers and world lifecycle

**Use this when** you decide where code runs, how often, and what happens when the player changes world.

## Rule 1: run everything on the game thread

UE4SS offers several ways to run Lua. Use the game-thread ones.

| Function | Thread | Use |
|---|---|---|
| `LoopInGameThreadWithDelay(ms, fn)` | game | **the main loop**; used by nearly every mod |
| `ExecuteInGameThread(fn)` | game | hop from anywhere to the game thread |
| `LoopAsync(ms, fn)` | **second thread**, no UE4SS lock | avoid; **deprecated in the official docs** (as are `ExecuteAsync` and `ExecuteWithDelay`) |
| `LoopInGameThreadWithDelay`, `ExecuteInGameThreadWithDelay`, `...AfterFrames`, `RetriggerableExecuteInGameThreadWithDelay` | game | official timer API: each returns a **handle** for `CancelDelayedAction`, `PauseDelayedAction`, `UnpauseDelayedAction`, `ResetDelayedActionTimer`, `IsDelayedActionActive`; actions are owned by the mod that made them |
| `ExecuteWithDelay(ms, fn)` | | one-shot delay |
| `RegisterKeyBind` callback | **not the game thread** (measured on our build 2026-11-20: thread 18524, `IsInMainModThread=true`) | set a flag only, or avoid ([input](input.md)) |
| `RegisterHook` callback | the thread of the hooked call, usually game | record only ([hooks-and-events](hooks-and-events.md)) |

Evidence: Starfall found Lua on the second thread crashed when a hook fired on the game thread. NoAutoPickup, AutoTool and FishingSliders all comment that `LoopAsync` callbacks run "without UE4SS's lock". If the game-thread timer does not exist on an old build, hop back with `ExecuteInGameThread` and keep **one** call outstanding:

```lua
local queued, at = false, 0
LoopAsync(500, function()
  if queued and os.clock() - at > 5 then queued = false end   -- clear a stuck one
  if queued then return false end
  queued, at = true, os.clock()
  if not pcall(ExecuteInGameThread, function() queued = false; pcall(mainTick) end) then queued = false end
  return false
end)
```

## Rule 2: one loop, flags in, work out

```lua
local REQ = {}                                   -- hooks, keys and Mod Menu set flags here
local function tick()
  if REQ.open then REQ.open = false; openWindow() end
  scanIfDue(); updateTracked(); saveIfDirty()
end
LoopInGameThreadWithDelay(100, function() pcall(tick) end)
```

Tick rates seen: 20 ms input sampler (MapMarkers, only while the map is open), 33 ms key poll (FishingSliders), 50 ms minimap follow (ours), 100 ms main (MapMarkers, AutoTool), 250 ms (FishingSliders, Starfall), 500 ms (NoAutoPickup), 1 s (PenguinFinder, SkillPets skill polling). Split fast and slow work: a fast loop for input and per-frame placement, a slow one for scans.

## Rule 3: never start a UE4SS timer inside a timer callback

Starfall: the game-thread timer list moved under the walker and crashed (a reload sent through a dev inbox restarted loops from inside one). Its fix, a **timer pump**:

```lua
local timers = {}                                 -- name -> { fn, ms, due, once }
local function pump()                             -- the ONLY UE4SS timer, started once per session
  local now = os.clock()
  for name, e in pairs(timers) do
    if now >= e.due then
      if e.once then timers[name] = nil else e.due = now + e.ms/1000 end
      pcall(e.fn)
    end
  end
end
ExecuteInGameThread(function() LoopInGameThreadWithDelay(15, pump) end)   -- ExecuteInGameThread uses a separate queue
function loop(name, ms, fn) timers[name] = { fn=fn, ms=ms, due=os.clock()+ms/1000 } end
function after(ms, fn)      timers["after#"..n] = { fn=fn, once=true, due=os.clock()+ms/1000 } end
```

Naming a loop replaces the old one. Starting or stopping touches nothing in UE4SS, so it is safe from anywhere, and it makes reload easy. (Starfall is MIT: its `ss.lua` can be reused with the notice.)

Note: the official delayed-action API (handles, cancel, pause) **exists on our build** (measured: `MakeActionHandle`, `CancelDelayedAction`, `ExecuteInGameThreadWithDelay` are present; `LoopInGameThreadWithDelay` returns a numeric handle). Whether starting a timer from inside a timer callback is safe on our build is **untested**; keep the pump pattern, or probe it, before relying on handles from inside callbacks.

**Find out which thread you are on** instead of guessing (official docs): `IsInGameThread()`, `GetCurrentThreadId()`, `GetGameThreadId()`, `IsInAsyncThread()`, `IsInMainModThread()`. Measured on our build (2026-11-20): `ExecuteInGameThread`, `LoopInGameThreadWithDelay`, `NotifyOnNewObject`, a `/Script/` `RegisterHook` and the mod's main chunk all run on the game thread; `LoopAsync` runs on another thread; **`RegisterKeyBind` callbacks run on a separate "main mod thread"**, concurrently with the game thread and sharing the Lua state.

## Rule 4: wait before touching the world

| Delay | Where |
|---|---|
| 4 s | AurelianUI before building its minimap |
| 5 s | ResourceAtlas farm scan after world up, plus `bIsRegistered` check |
| 10 s | AutoTool after the pawn exists |
| 15 s | CollectionLog catalog build (`S.readyAt`) |
| 20 s | MapMarkers `BOOT_GRACE` before any `FindAllOf` |
| 40 s | Slayer quiet period |

World load is a stall: do not run `FindAllOf` sweeps during it. Gate expensive first-time work behind a readiness time, and gate field reads on a readiness field where one exists (`FarmSlotComponent.bIsRegistered`). ResourceAtlas found its crash was null crop meshes and not timing, but kept a small margin.

## Rule 5: reset everything when the world changes

Objects from a closed world are freed. Even `IsValid()` on a stale pointer can crash natively.

How to detect a change:
- `localPC()` returns nil (no world, main menu): drop everything (MapMarkers, NoAutoPickup).
- A key combining controller name and world: `full(pc).."|"..full(pc:GetWorld())` changes (AutoTool); `pcName.."|"..playerName` (CollectionLog).
- `RegisterLoadMapPostHook(function(_, world) ... end)` (RuneSchema).

What to reset (Slayer's checklist): window and widget handles, pad state, prompt UI, queued NPCs (drop those queued up to the last tick spent in the old world, keep later ones), stored pause menu, retire and retry flags, timers, tile or card state. Drop references; **do not call methods on them**.

Per-world UI is built once and then only shown, hidden and rewritten ([ui-construction](ui-construction.md)).

## Rule 6: hot reload needs a trampoline

Hooks, key binds and console commands cannot be unregistered from Lua.
- Starfall registers each hook **once** and dispatches through a table of named handlers that reload can replace.
- RSDWTools' hotkeys capture `my_gen = _generation` and return early when `_generation ~= my_gen`.
- Starfall's runtime file can be run again safely: state lives in one global table, only functions are redefined.

## Staged start-up for fragile features

AurelianUI's minimap runs a state machine (`wait`, `init`, `detect`, `run`, `off`) with a retry timer in each state and writes each step to a report file. A step that cannot work turns off **only that part**.

## Seen in

[sources/Starfall.md](../sources/Starfall.md) (pump), [sources/AurelianUI-Minimap.md](../sources/AurelianUI-Minimap.md) (state machine), [sources/Slayer.md](../sources/Slayer.md) (reset checklist), [sources/NoAutoPickup.md](../sources/NoAutoPickup.md) (fallback loop). Crashes behind these rules: [reference/stability-rules.md](../reference/stability-rules.md).
