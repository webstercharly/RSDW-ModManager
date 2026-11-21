# Guide: diagnostics, probing and testing

**Use this when** you investigate an unknown game function, find a crash, or decide whether a technique works.

## Logging

```lua
local TAG = "[MyMod] "
local function log(msg) print(TAG .. tostring(msg) .. "\n") end        -- appears in UE4SS.log
```

- Log version and config at startup (`loaded v1.0.0: ...`).
- **Log each step of a risky first-time operation** so a native crash leaves the last call made in the log (ResourceAtlas logs every step of its first two farm scans).
- Log a decision **once** per reason (`logOnce(key, msg)`); cap repeated errors (first 3-5).
- Log the first time a game build differs from what you expect ("this build's health bar has no DebugHealthValues widget") and then turn only that feature off.
- A line per hook that arms ("kill counting armed (try 2)").

Logs to read after a crash: `ue4ss/UE4SS.log` and `%LOCALAPPDATA%/RSDragonwilds/Saved/Logs/RSDragonwilds.log`. A native crash may leave no Lua error. UE4SS also writes `.dmp` files (`[CrashDump] EnableDumping = 1`); three exist and are unexamined.

## Report files

AurelianUI writes every minimap step to `AurelianUI_minimap_report.txt` and keeps the previous launch's file as `..._previous.txt` so it survives a crash. Also writes lists of what it found (`..._hud_tree.txt`, `..._hotbar_slots.txt`, attribute values). Use for state that does not belong in the shared log.

## Probe first, then ship

The authors' habit, visible in every header comment:
1. Write an **opt-in, one-shot probe** (RSDWTools: "never spawn, mutate parameters, or deliver from a hook").
2. Record dated findings in a doc (`docs/probe-results-2026-10-01.md`).
3. Write the feature from the finding, with the date in the code comment ("measured 2026-10-20").
4. Keep the crash reason next to the rule ("each one was paid for by a crash").

Probe cautions:
- Read named fields only; do not dump every property (crash).
- Do not call functions with side effects (`ClearPin` hung the thread).
- Use `FindAllOf` sparingly; some objects are freed.
- Compare a test world to a real one: dead mirrors look correct in a short test (health).

## A ready probe for the UE4SS build

`Tools/Probes/UE4SSProbe/` measures, on our installed loader: which documented globals exist, which thread each callback type runs on (including key binds), whether out-parameter tables leak registry references, which table receives out values, and (opt-in) soft-reference reads and timer nesting. It is inert until a user copies it into `ue4ss/Mods/`, appends results as it goes so a crash leaves the last step, and its README maps each result line to the guide entry to update. Use it as the template for new probes. Also useful: `UE4SS.log` itself, for example counting `[push_weakobjectproperty]` lines to see a silent failing write.

## Crash dumps and native-mod checks without a debugger

`Tools/Diagnostics/Triage-UE4SSDump.py` summarises a UE4SS `.dmp` (exception, faulting module and offset, registers, a heuristic stack) and `Tools/Diagnostics/Check-NativeModAbi.py` tests whether a native mod's imports resolve against a candidate `UE4SS.dll`. Setup and usage are in each script's header; both need a throwaway virtual environment (`minidump`, `pefile`) and only read files. Compare the **module and offset** across dumps: the same offset is the same bug. There is no PDB, so offsets are not named. Past results: `Tools/Diagnostics/results/`.

## Console commands

```lua
RegisterConsoleCommandHandler("mymod_status", function(fullCommand, params, outputDevice)
  outputDevice:Log("ok")          -- writes to the console output
  return true
end)
```

Starfall registers once and dispatches through a table (reload-safe). RSDWTools offers `rsdwt_cmd <line>`, `rsdwt_probe_debug`, `rsdwt_hotkeys_reload`. Console execution from Lua: `KismetSystemLibrary:ExecuteConsoleCommand(...)` works; `PlayerController:ConsoleCommand` traps ("UObject instance is nullptr": not a UFunction). To list every CVar run the engine commands `Help`, `DumpConsoleCommands`, `DumpConsoleVariables` through it.

## Introspection tools other mods built

- RSDWTools `feature_introspect`: for an actor, the class chain and per class the fields (name, type, value, readable) and methods (name, signature). Output JSON for a viewer.
- `safety.classify` for unknown values ([reading-writing-values](reading-writing-values.md)).
- `fn:ForEachProperty(...)` on a UFunction object lists its parameter names (QuestLog verifies `MapKey` before using it).
- Dumping the widget tree to a text file once per load (AurelianUI) **but never a whole-HUD geometry scan** (it crashed).
- RSDWTools' generated catalogs (`json/BPData.json`, 2.4 MB) are a ready search target for class and field names.
- UE4SS settings include object-dump and header-generator sections ([reference/ue4ss.md](../reference/ue4ss.md)); how to run them is not documented here yet.

## Test plan hygiene

- Keep a test plan where unchecked means "not proven in game" (our `Docs/TEST_PLAN.md` rule). Do not tick from syntax checks.
- Test: main menu to world, **Exit to Main Menu and re-enter**, new character, second world, controller only, key spam, map open and close repeatedly, pause menu open and close, co-op client if relevant.
- Slayer's native crash came from exactly "Exit to Main Menu, re-enter, press a key near an NPC".
- Validate files before running: `luaparse` for Lua, `ConvertFrom-Json` for JSON (our `.agent/WORKSPACE.md` commands).
- A harness that runs `core/` logic outside the game (Starfall's design allows it).

## Fault handling in the mod

- Wrap each part in `pcall`; count consecutive failures; disable only that part after three (ResourceAtlas).
- A failed route marks itself failed for the session and a fallback takes over (SkillPets).
- Warn once and do nothing when a required field is missing (NoAutoPickup).
- If a build step fails, log it and record it as `off` for the world instead of retrying every tick.

## Seen in

[sources/AurelianUI-Minimap.md](../sources/AurelianUI-Minimap.md), [sources/RSDWTools.md](../sources/RSDWTools.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/Starfall.md](../sources/Starfall.md).
