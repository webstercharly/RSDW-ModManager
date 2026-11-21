# UE4SS reference

Sources, in order of authority:
1. **Official docs** exported from upstream (`References/UE4SS/Docs/upstream-v4.0.0/`, tag v4.0.0, commit `30afe5ff`, MIT). Marked **[docs]**.
2. **Upstream git history and issues**, checked 2026-11-20. Marked **[git]**.
3. **Our install**: `UE4SS.log`, `UE4SS-settings.ini`, bundled mods. Marked **[install]**.
4. **How the mods in this library call it**. Marked **[mods]**.

Status: the API surface is now documented from the source. What is still missing is behaviour **on our installed build in game** (see "Gaps").

## Our build against upstream

| Fact | Evidence |
|---|---|
| Installed: `UE4SS - v3.0.1 Beta #0 - Git SHA #f6d5f942`, shipping, MSVC | [install] `UE4SS.log` |
| `f6d5f942` is upstream commit 2026-09-14 `chore: Changelog`, **1135 commits after v3.0.1** (hence "build 1135"), contained in v4.0.0, 96 commits older | [git] |
| `0196ef29` (2026-03-27, build 944) is an **ancestor** of `f6d5f942`: the "946" archive in `References/UE4SS/Candidates/` is simply older | [git] |
| `f58e8f84` (2026-09-21, build 1140) is not an ancestor of ours; both are in v4.0.0 | [git] |
| Engine: `EngineVersionOverride` 5.6 | [install] ini |
| Lua API docs differ between our commit and v4.0.0 in only five files (`FWeakObjectPtr`, `TArray`, `UObject`, `print`, new `println`) | [git] `docs-delta-f6d5f942-to-v4.0.0.diff` |

### Fixes upstream made **after** our build (build numbers = commits since v3.0.1)

| Build | Fix | Why it matters here |
|---|---|---|
| 1151 | `FWeakObjectProperty` setter and `UObject ==` (#1414) | Our log prints `[push_weakobjectproperty] Operation::Set is not supported`: a Lua assignment to a weak-object property silently fails on our build. Measured 2026-11-20: about **1 hit per second** from world load (338 in 6 minutes) in a session running minimap service 0.2.4, whose HANDOFF entry says the `widget.MapViewComp` write was already removed, so the **writer is unidentified** (not necessarily the minimap). Bisect procedure in `Tools/Probes/UE4SSProbe/README.md` |
| 1163 | Non-struct/array out params corrupted following params (#1454) | Calls with several out params (EnemyHPNumbers' attribute read) behaved oddly; the "all outs land in the first table" quirk may change after this |
| 1164 | **Release the registry reference to Out parameter tables after UFunction calls (#1452)** | The leak SkillPets' RegSweep works around **does not exist from 1164** |
| 1171 | Buffer overflow on UFunctions with very large param structs | |
| 1172-1174 | **Soft object pointer runtime layout (#1433, PR #1465)** | Fixes the crash on soft pointer copies; reported on build 1135 and 1136 by an independent tester, last good build 1029 |
| 1183 | Deadlock when a Lua hook or `NotifyOnNewObject` callback calls `RestartCurrentMod` while a mod is uninstalling | |
| 1187 | Broken `UObject:CallFunction` fixed | |
| 1190, 1213 | **UE 5.6: `FSoftObjectPath` sub-path is UTF-8 (#1486)**, copy over-read crashed via `FWeakObjectPtr::operator=` / `AllocateSerialNumber` | Dragonwilds is UE 5.6; reported on 1183, fix pushed 2026-10-31, **verified by code review only** in the issue |
| 1199, 1203 | Wait for running game-thread actions before closing a mod's Lua state; release the shared Lua lock when a state closes | shutdown and reload races |
| 1207, 1211 | Growing a `TArray` with constructible elements; stale code in `TArray` indexing | a regression window existed inside 1207-1210 |
| 957 (already ours) | Use-after-free in the string intern pool (#1271), "most commonly Lua GC'd strings from UObject member access" | in our build already |

The staged candidate `3.0.1-1217-r2` is **verified** (git ancestry plus the fork's own release notes) to be the unmodified upstream build 1217, which contains every fix above. See "Staged 1217-r2 assessment".

**Caution before swapping loaders:** v4.0.0 contains **breaking C++ mod API changes** (`FSoftObjectPath` and soft pointer members replaced by accessors, a new event dispatch system for C++ mods, #1431). Native mods built for older headers (RuneSchema, RSDWTools wrapper, MiniMap, Class Specialisations) may fail to load or crash. Test them first; back up the live loader.

## Measured on our build (UE4SSProbe, 2026-11-20 15:00, build 1135, UE 5.6)

Raw results: `Tools/Probes/UE4SSProbe/results/results-20261120-150030-build1135.txt`. These outrank the upstream docs for our install.

| Question | Result |
|---|---|
| Which documented APIs exist on 1135? | **53 of 54.** The whole delayed-action API (`ExecuteInGameThreadWithDelay`, `MakeActionHandle`, `CancelDelayedAction`, ...), all thread-id functions, `ExecuteInGameThread` with `EGameThreadMethod`, `RegisterKeyBindAsync`, `IsKeyBindRegistered`, and the dumpers (`GenerateLuaTypes`, `DumpUSMAP`, ...) exist. Only `println` is missing (added upstream at build 1168). `FName` and `FText` are callable **userdata**, not plain functions. `ModRef` is userdata. `EngineTickAvailable` and `ProcessEventAvailable` are both `true` |
| Versions | `UE4SS.GetVersion()` 3.0.1, `UnrealVersion` 5.6, Lua 5.4 |
| Game-thread callbacks | `ExecuteInGameThread`, `LoopInGameThreadWithDelay`, `NotifyOnNewObject` and a `/Script/` `RegisterHook` (`PlayerController:ClientRestart`) all ran on the game thread (thread 33388). The mod's **main chunk** also ran on it (`IsInMainModThread=false`) |
| `LoopAsync` | Runs on a different thread (37128), `IsInAsyncThread=true`: it is not a game-thread loop |
| **`RegisterKeyBind` callbacks** | **Run on a different thread (18524), not the game thread**: `IsInGameThread=false`, `IsInAsyncThread=false`, `IsInMainModThread=true`. This is the "main mod thread". It runs concurrently with the game thread in the same Lua state, which is the mechanism behind FishingSliders' key-spam crash |
| Key mashing | 45 presses in 17 s (up to about 6 per second) with only a counter in the callback and light game-thread Lua: **no crash**. Key presses alone do not crash it; FishingSliders had heavy game-thread Lua running at the same time |
| Out-param table layout | `GetViewportSize(a, b)` put `SizeX` and `SizeY` **both in table `a`**, nothing in `b`: the old layout ("all outs in the first table") is confirmed on 1135 |
| **Out-param registry leak** | **Confirmed.** 300 calls grew numeric registry slots 11 to 609 (+598, **1.99 per call**, one per out table) and Lua memory 115 to 178 KB after a full GC. Fixed upstream at 1164 |
| Weak-object `Operation::Set` warning | About once per second after world load (1.03 to 1.08 s apart). Bisecting with the log timeline (toggle one feature, watch the line stop and resume) traced it to a feature that removed and re-added a gameplay effect every second. **Root cause (2026-11-20):** its "already active" test compared two UObject wrappers with `==`, which is **always false on build 1135** (wrapper `==` is identity there; each lookup returns a fresh wrapper; pointer `__eq` arrived at build 1151). Passing the effect handle (a struct holding weak pointers) each way is what UE4SS logs. Fixed by comparing `GetAddress()`. **Log-confirmed on a fresh launch:** 1 warning in 71 s afterwards (old behaviour about 66). No link to the three crashes |
| Not yet run | `SoftRefRead`, `TimerNesting`, the weak-writer bisect, the crash dumps |

## Crash dump triage (2026-11-20, static, read-only)

Tools: `Tools/Diagnostics/Triage-UE4SSDump.py` (raw output: `Tools/Diagnostics/results/crash-triage-2026-11-20.txt`). No PDB is held, so offsets are not symbolised, and stack frames are a heuristic scan.

| Dump | Exception | Fault location |
|---|---|---|
| `crash_2026_11_16_15_14` | access violation, **read of 0x0** (null) | `UE4SS.dll +0x2ac4b3` |
| `crash_2026_11_16_20_44` | access violation, **read of 0xa** | `UE4SS.dll +0xc5f53d` |
| `crash_2026_11_20_10_46` | access violation, **read of 0xFFFFFFFFFFFFFFFF**; `rax` and `rbx` hold the bytes `5d 88 'v' 'a' 'l' 'u' 'e' 'j'` (string data used as a pointer) | `UE4SS.dll +0xc6d5c0` |

What this supports:
- **All three faults are inside `UE4SS.dll`**, whose build timestamp in every dump is 2026-09-14 09:09 UTC: our installed build 1135.
- Each faulting thread's stack is overwhelmingly `UE4SS.dll` frames, clustered in two regions (`+0xb9...` to `+0xc7...`, and `+0x2ac...`), which is the Lua binding and object-access code. **No frames in `RSDWTools.dll` or `main.dll`** (they were loaded but are not on the stacks), and the game exe appears only through stale values.
- The first dump's fault (`+0x2ac4b3`, a null read, in a function starting at `+0x2ac4a0`) is within about 0x424 bytes of the `UE4SS.dll +0x2AC8D7` that MapMarkers' author recorded for the "`IsValid` on freed memory" crash (3 of 3). Same code region, not proven the same function. It supports the rule that a stale object handle can crash natively ([stability-rules](stability-rules.md) rule 1).
- The third dump (string text used as a pointer, `-1` read) is the same crash class as the soft-pointer and weak-pointer layout bugs fixed upstream (#1433, #1486), but nothing here ties it to them.

What it cannot say: which mod's Lua triggered each crash, or whether upstream fixed these particular crashes. Three different offsets means three different code paths, so one loader fix is unlikely to cover them all; a newer loader removes known bugs but proves nothing about these.

## Staged `1217-r2` assessment (static, 2026-11-20)

Facts (git history, the fork's release notes, the staged files):
- The Dragonwilds repo `MichaelRyan2319/RSDragonwilds-UE4SS` states that `v3.0.1-1217` is the **unmodified upstream `experimental-latest` build**; only `ue4ss/Mods/mods.txt` and `mods.json` changed (example mods off). `-r2` (release commit `01dfdb25`, 09 Nov) only changes the zip layout; "nothing in the mod changed". Its README says the game's Unreal build 26162923 (UE 5.6) works without extra setup.
- **Upstream build 1217 is commit `4fb9b61` (2026-11-07).** By git ancestry it **contains all of**: soft pointer layout (`6eef940`, #1433), PR #1465, UTF-8 sub-path (`f673aac`) and the sub-path accessor (`34b7c6a`, #1486), the out-param registry-leak fix (`5e62799`), out-param corruption fix (`3a4b642`), the weak-object setter (`03dbd5c`), Lua-state shutdown fixes (`0c5cb73`) and the queued-event deadlock fix (`97c5642`). Its source is **identical to v4.0.0**.
- Staged `UE4SS.dll` (20,708,352 bytes) and `dwmapi.dll` differ from the installed ones. The staged settings file differs only by: `HotReloadKey = R`, empty `EngineVersionOverride` (ours is 5.6), new `PointerHash = Auto`, font scale. The staged `mods.txt` switches every bundled mod off and has no `RSDWTools` line. Staged `BPModLoaderMod` and `ConsoleEnablerMod` scripts differ from ours; `UEHelpers`, `ConsoleCommandsMod`, `CheatManagerEnablerMod`, `BPML_GenericFunctions` are identical.
- **Native mods:** the only DLL-bearing mod installed is RSDWTools (`dlls/main.dll`, plus `RSDWTools.dll`, a shared-memory bridge with no UE4SS import). `main.dll` imports 29 symbols from `UE4SS.dll` (`CppUserModBase` and its virtual callbacks, `Lua::LuaMadeSimple` string/integer/table helpers, `DefaultTargets::Output`); **all 29 resolve against the staged `UE4SS.dll`** (`Tools/Diagnostics/Check-NativeModAbi.py`). Upstream's changelog states the new C++ events replace the virtuals "for ABI reasons" and that "no new virtual functions will be added to CppUserModBase, and no existing virtual functions will be removed". The wrapper uses none of the soft-pointer members that changed. This is a **symbol and documentation check, not a runtime test**: member layout changes are invisible to it.

Swap recipe, **for the user to decide and perform** (an agent must not do this unprompted):
1. Close the game. Back up `Binaries\Win64\dwmapi.dll` and the whole `Binaries\Win64\ue4ss\` folder to a dated folder.
2. From the staged `Candidates\3.0.1-1217-r2\extracted\Binaries\Win64\` copy **only** `dwmapi.dll` and `ue4ss\UE4SS.dll`. **Keep** our `ue4ss\UE4SS-settings.ini`, our `ue4ss\Mods\mods.txt` (the staged one disables everything) and everything in `Mods\`. Optionally add `PointerHash = Auto` under `[EngineVersionOverride]`.
3. Start the game and read the first lines of `UE4SS.log` for the new version string.
4. Re-run `Tools/Probes/UE4SSProbe` (expect `println` present, no registry growth, possibly a different out-param layout) and check that RSDWTools, QuestLog, CollectionLog, EnemyHPNumbers and the Mod Manager still work. Then run the soft-reference probe.
5. Roll back by restoring the backup if anything fails. Antivirus may flag the new `dwmapi.dll`.

Not covered: runtime behaviour of RSDWTools' wrapper on the new loader, and whether our own mods hit behaviour changes (out-param layout, `TArray` handling). Test, do not assume.

## Official API facts [docs]

### Hooks

```lua
local preId, postId = RegisterHook(path, cb1 [, cb2])        -- returns two ids; both go to UnregisterHook
UnregisterHook(path, preId, postId)
```

- **Callback timing depends on the path.** If the path starts with `/Script/`: `cb1` runs **before** the function and the optional `cb2` runs after. **Otherwise (Blueprint functions): `cb1` runs after the function and `cb2` does nothing.** Our guides previously said "pre"; for `/Game/...` hooks it is post.
- The function **must already exist in memory**. Delegate functions are not supported.
- Callback parameters: `self` and each argument arrive as `RemoteUnrealParam` (or `LocalUnrealParam`): `p:get()` reads, **`p:set(value)` writes** (so a pre-hook can change an argument), `p:type()` names the type. They have **no** `IsValid()` or `GetAddress()`.
- A callback's return value is converted to a UE value and **overrides the function's return**; `nil` or no return leaves it.
- Hook callbacks "are not guaranteed to execute on the game thread; they execute wherever the game (or engine) designed them to".

### NotifyOnNewObject

Runs when an object of the class (inheritance included) is constructed through `StaticConstructObject_Internal`. The class need not exist yet. Returning `true` unregisters that callback. **Do not register more than one callback for the same class** across your mod (or others): "could cause performance issues ... seen in the wild". Combine work into one callback.

### Timers and threads

| API | Notes |
|---|---|
| `LoopInGameThreadWithDelay(ms, cb)` | returns a handle; runs until `CancelDelayedAction(handle)` |
| `ExecuteInGameThreadWithDelay(ms, cb)` / `(handle, ms, cb)` | second form only starts if the handle is not active (UE `Delay` behaviour) |
| `RetriggerableExecuteInGameThreadWithDelay(handle, ms, cb)` | restarts the timer on each call: debounce |
| `ExecuteInGameThreadAfterFrames(n, cb)`, `LoopInGameThreadAfterFrames(n, cb)` | need the EngineTick hook (`EngineTickAvailable`) |
| `MakeActionHandle()`, `CancelDelayedAction`, `PauseDelayedAction`, `UnpauseDelayedAction`, `ResetDelayedActionTimer`, `IsDelayedActionActive` | control by handle |
| `ExecuteInGameThread(cb [, EGameThreadMethod.ProcessEvent \| EngineTick])` | queues on the game thread; falls back to the other method if unavailable; globals `EngineTickAvailable`, `ProcessEventAvailable`. `ProcessEvent` fires several times per frame, `EngineTick` once |
| `ExecuteAsync`, `LoopAsync`, `ExecuteWithDelay` | **deprecated**; run asynchronously (not on the game thread). `LoopAsync` stops when its callback returns `true` |
| `IsInGameThread()`, `GetGameThreadId()`, `GetCurrentThreadId()`, `IsInAsyncThread()`, `IsInMainModThread()`, `GetAsyncThreadId()`, `GetMainModThreadId()` | **diagnose which thread you are on**; compare `ThreadId` values |

"All delayed actions execute on the game thread ... owned by the mod that created them, preventing cross-mod interference." The ini key for the default method is `DefaultExecuteInGameThreadMethod` in the shipped settings (the docs page names it `DefaultGameThreadExecutionMethod`; the file wins).

### Key binds

`RegisterKeyBind(Key.O, cb)` and `RegisterKeyBind(Key.O, {ModifierKey.CONTROL, ModifierKey.ALT}, cb)`. **Callbacks run only when the game or the debug console is in focus.** `IsKeyBindRegistered(key [, mods])` checks. The `Key` and `ModifierKey` tables are documented (`table-definitions/key.md`, `modifierkey.md`). A key bind's callback thread is not stated in the docs; the key-thread crash report comes from FishingSliders ([mods]), and `GetCurrentThreadId()` inside a callback will tell you.

### Objects and finding

- `UObject` members via `.Name` and `:Func()`; `__eq` compares underlying pointers and is safe on invalid objects (added after our build). `GetFullName()`, `GetFName()` (**FNames from `__index` are returned by reference**), `IsValid()`.
- `FindAllOf(shortClass)` returns **non-default instances** only, `nil` if none; it "cannot be used to find non-instances or default instances". `FindFirstOf` likewise. Template or archetype objects can still appear (Slayer saw the `/Game` archetype), so keep the defensive filters.
- `LoadAsset(path)` **must be called on the game thread** (a hook or console-command callback, for example).
- `StaticConstructObject(class, outer, [FName], flags..., [template UObject], ...)`; there is an overload taking the 64-bit FName value.
- `Mod` (the `ModRef` global): `SetSharedVariable(name, v)`, `GetSharedVariable(name)`. Allowed types: `nil`, `string`, `number`, `bool`, `UObject`, `lightuserdata`. **They are not reset on hot reload**, and **any mod can overwrite any variable**. "Do not share transient objects like actors": share class defaults only.

### Containers

- `TArray`: 1-indexed `arr[i]`, assignment, `#arr`, `GetArrayNum()`, `GetArrayMax()`, `GetArrayAddress()`, `GetArrayDataAddress()`, `Empty()`, `ForEach(function(index, elem) ... end)` where `elem:get()` / `elem:set(v)`, and **returning `true` from the callback breaks the loop**.
- `TMap`: `#map`, `Find(key)` (**throws if missing**), `Add(key, value)` (replaces), `Contains(key)`, `Remove(key)`, `Empty()`, `ForEach(function(key, value) ... end)` with the same `get/set` and early break; mutating a key is undefined.
- Also documented: `TSet`, `FName`, `FString`, `FText`, `FUtf8String`, `FAnsiString`, `FWeakObjectPtr`, `UFunction`, `UClass`, `UStruct`, `UScriptStruct`, `UEnum`, `UDataTable`, `UWorld`, `AActor`, `FOutputDevice`, property classes (`ObjectProperty`, `ArrayProperty`, `StructProperty`, delegate properties...).

### Other documented globals

`RegisterBeginPlayPreHook/PostHook`, `RegisterInitGameStatePreHook/PostHook`, `RegisterProcessConsoleExecPreHook/PostHook`, `RegisterULocalPlayerExecPreHook/PostHook`, `RegisterCallFunctionByNameWithArgumentsPreHook/PostHook`, `RegisterConsoleCommandHandler`, `RegisterConsoleCommandGlobalHandler`, `RegisterCustomEvent`, `RegisterCustomProperty`, `FindObject`, `FindObjects`, `ForEachUObject`, `CreateInvalidObject`, `IterateGameDirectories`, `FName`, `FText`, `print`, `println` (newer), `ModManagement`, and the dumpers (`DumpAllObjects`, `DumpAllActors`, `DumpStaticMeshes`, `DumpUSMAP`, `DumpJMap`, `GenerateSDK`, `GenerateUHTCompatibleHeaders`, `GenerateLuaTypes`). Note **`GenerateLuaTypes`** and **`DumpUSMAP`** answer two items on our earlier gap list: how to produce Lua type stubs and a `.usmap`. Read the matching docs file before calling any of them.

Docs location: `References/UE4SS/Docs/upstream-v4.0.0/extracted/docs/lua-api/` (`global-functions/`, `classes/`, `table-definitions/`, `examples.md`), plus `guides/creating-a-lua-mod.md`, `feature-overview/` (dumpers, live view, Blueprint modloader, universal mods) and `upgrade-guide.md`.

## Loading and settings [install] [docs]

- `Mods/mods.txt` lines `Name : 1`; a folder with `enabled.txt` also loads. Stock entries include `ConsoleCommandsMod`, `ConsoleEnablerMod`, `BPML_GenericFunctions` and `BPModLoaderMod`.
- Entry `Scripts/main.lua`; **each mod has its own Lua state**; `ModRef` global; `debug.getinfo(1,"S").source` gives the file path. `package.loadlib` works.
- Settings we run: `EnableHotReloadSystem = 0`, `EnableAutoReloadingLuaMods = 0`, `DefaultExecuteInGameThreadMethod = EngineTick`, `DefaultFNameToStringMethod = Scan`, `UseCache = 1`, `SecondsToScanBeforeGivingUp = 120`, `EngineVersionOverride 5.6`, `[CrashDump] EnableDumping = 1, FullMemoryDump = 0`, `[Debug] ConsoleEnabled = 0, GuiConsoleEnabled = 0`, all hook toggles `= 1` (`HookProcessInternal`, `HookInitGameState`, `HookLoadMap`, `HookBeginPlay`, `HookEndPlay`, `HookEngineTick`, `HookUObjectProcessEvent`, ...). Upstream added `PointerHash` (auto-detect pointer hashing) which our file lacks.
- `[ObjectDumper]`, `[CXXHeaderGenerator]`, `[UHTHeaderGenerator]`, `[SDKGenerator]` sections exist for the dumpers.

## UEHelpers [install]

Functions: `GetUEHelpersVersion`, `GetEngine`, `GetGameInstance`, `GetGameViewportClient`, `GetPlayerController`, `GetPlayer`, `GetWorld`, `GetPersistentLevel`, `GetGameModeBase`, `GetGameStateBase`, `GetWorldSettings`, `GetWorldContextObject`, `GetAllPlayerStates`, `GetAllPlayers`, `GetActorFromHitResult`, `GetGameplayStatics`, `GetKismetSystemLibrary`, `GetKismetMathLibrary`, `GetKismetStringLibrary`, `GetKismetTextLibrary`, `GetGameMapsSettings`, `FindFName`, `AddFName`, `FindOrAddFName`. Invalid results are `CreateInvalidObject()`, never nil. `GetPlayerController` does **not** test `IsLocalController()`, so it can return a remote player's controller in multiplayer. Type stubs: `assets/Mods/shared/Types.lua` in the docs export.

## Idioms and findings from the mods [mods]

- Out params: pass an empty table per out param; in this build all outs landed in the first table (EnemyHPNumbers, measured). Behaviour changed upstream at 1163-1164; re-test on any new loader.
- Registry reference leak per out-table call (SkillPets); fixed upstream at 1164.
- Soft object properties crash on 1135 (CollectionLog, AurelianUI, ResourceAtlas); fixed upstream at 1172-1174 and 1190/1213.
- Hook arming: Blueprint functions exist only after their class loads; retry (Slayer, Starfall).
- `RegisterKeyBind` callbacks crashed under key spam (FishingSliders); the docs do not say which thread they run on.
- `LoopAsync` and timers started inside timers crashed (Starfall, NoAutoPickup); `LoopAsync` is now deprecated.
- Userdata that is not a UObject (FText, FName, FString, structs, soft refs) crashes on `GetClass()` (RSDWTools).

## Build-specific problems: status

| Problem | Reported on | Fixed upstream | Our build |
|---|---|---|---|
| Soft pointer read crash (#1433) | 1135, 1136 | 1172-1174 | **exposed** |
| UE 5.6 soft path crash (#1486) | 1183 | 1190, 1213 | **exposed** |
| Out-table registry leak (#1452) | SkillPets on 1135 | 1164 | **measured: leaks 1.99 refs per call (2026-11-20)** |
| Out-param corruption (#1454) | | 1163 | **exposed** |
| Weak-object property set (`Operation::Set is not supported`) | our log | 1151 | **exposed** |
| Shutdown and reload races | | 1183, 1199, 1203 | **exposed** |
| `IsValid()` on freed memory | MapMarkers, Slayer | not a UE4SS fix: engine frees objects | keep the rule |
| `RegisterKeyBind` under key spam | FishingSliders | not identified | **callbacks run off the game thread (measured 2026-11-20)**; crash not reproduced with 45 presses and light load |
| `RegisterHook` on a native (non-UFunction) function | RSDWTools | by design | keep the rule |
| Material functions on non-dynamic materials | AurelianUI | by design | keep the rule |

## Gaps that remain

1. **Nothing is tested on our build in game.** The version map says what upstream fixed, not that the staged loader works with our native mods. A probe that measures items 3, the leak, the out-param layout, soft reads and timer nesting on our build is ready: `Tools/Probes/UE4SSProbe/` (inert until a user copies it into `Mods`; results table in its README). It has been parse-checked and dry-run against stub globals only.
2. ~~Whether the fork's `1217` includes the upstream fixes~~ **answered 2026-11-20**: it is the unmodified upstream build 1217 (only the example mods are switched off), and it contains every fix listed.
3. ~~Which thread `RegisterKeyBind` callbacks run on~~ **answered: not the game thread** (main mod thread). Still open: whether a key-spam crash reproduces under heavy game-thread Lua, and whether the 1199/1203 changes affect it.
4. ~~The three crash dumps are unexamined~~ **triaged 2026-11-20** (section above): all faults are inside `UE4SS.dll` build 1135. Still unknown: which mod's Lua triggered each, because there is no symbolised stack or Lua traceback.
5. ~~Which mod performs the once-per-second weak-object property write~~ **found and fixed 2026-11-20: a mod compared UObject wrappers with `==`, which is always false on build 1135, so it removed and re-added a gameplay effect every second (fix: compare `GetAddress()`). Fix log-confirmed.** The `push_weakobjectproperty` warning is no longer present in normal play; it only marks a weak-object write, so any future recurrence should be bisected the same way (toggle one thing, read the log timeline).
6. Exact `StaticConstructObject` argument meanings beyond class, outer, name and template.
7. How the dumpers behave on this game (`GenerateLuaTypes`, `DumpUSMAP`).
8. Object lifetime rules are still only what the mods learned; the docs state `IsValid()` but not when memory is reclaimed.
