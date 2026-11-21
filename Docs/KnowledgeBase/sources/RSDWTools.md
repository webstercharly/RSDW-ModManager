# RSDWTools: implementation guide

Source: `ue4ss/Mods/RSDWTools/` (the user's installed copy, read **in place**, not copied into `References/`). `scripts/`
holds about 91,000 lines of Lua across roughly 100 files, plus `RSDWTools.dll`, `dlls/main.dll`, `RSDWTools.exe` (a WPF
desktop app), `json/` catalogs and `ipc/` data. It is **another author's mod**, not ours. Its own `AGENTS.md` says the
Mod Manager must not depend on it. No licence file was found: learn, do not copy.

**What it does:** a large developer and cheat toolkit driven mostly from an external app: teleport, actor tools, player
stats, effects, skills, inventory and recipes, loadouts and gear swaps, world and weather, building probes, NPC driving,
transmog, cameras, world events, catalog dumps.

**Why read it:** it is the broadest record of what the game's reflected API exposes, and it documents several safety and
multiplayer lessons.

## Structure

```text
main.lua                     entry; requires features; registers console handlers; polls the bridge
bridge_shm.lua               wrapper over native globals BridgeLineInitCpp / PollRequestCpp / WriteAckCpp
command_line_router.lua      one dispatcher: "verb args" -> handler; header lists every verb
router_*.lua                 verb families (actor, build, camera, cvars, debug, enemy_events, navigation, npc, player, probe, ui, world)
feature_*.lua                one capability each (about 80), e.g. inventory, loadouts, gear_swap, ge, attr, field, skills,
                             world_settings, world_events, npc_drive, grab, teleport, camera, oculus*, foliage, transmog, ...
safety.lua                   shape classifier and guarded calls
feature_net.lua              local-player resolution for multiplayer
feature_hotkeys.lua          user-authored hotkeys, generation counter
feature_wheel_hook.lua       mouse wheel as a hotkey by polling
json/*.json, ipc/*.json      generated catalogs (BPData 2.3 MB, NPCData, NpcActionCatalog, PlayerAnimationCatalog, SpawnCatalog,
                             CompatibilityManifest) and user documents
tools/Generate-Catalog.ps1   out-of-game catalog builder
```

Everything is called by **verb lines**. The external app writes `player.heal 100`, the mod acks `ok <verb> <detail>` or
`err <reason>`. Console commands registered with `RegisterConsoleCommandHandler`: `rsdwt_help`, `rsdwt_cmd <line>`,
`rsdwt_bridge_status`, `rsdwt_hotkeys_reload`, `rsdwt_probe_debug`, `tele`, `scan`, `rsdwt_umg_text`.

A small defensive patch opens `main.lua`: it replaces `table.sort` with a wrapper that prints a trace and returns instead of
raising when called with a non-table. Evidence the author hit a UE4SS table returning something unexpected.

## Shape-based safety (`safety.lua`)

The problem and the answer are in [guides/mod-anatomy.md](../guides/mod-anatomy.md). Concrete classifier:

| Kind | Test | Allowed access |
|---|---|---|
| `nil`, `boolean`, `number`, `string`, `table` | `type()` | normal |
| `uobject` | userdata and `pcall(val:GetClass())` returns non-nil | full UObject methods |
| `text_like` | has `ToString` field but is not a uobject | `:ToString()` only (FText, FName, FString) |
| `soft_ref` | has `Get` field | `:Get()` then re-classify; never walk into the wrapper |
| `tarray` | `#val` works | length and iterate |
| `unsafe_ud` | userdata with none of the above | opaque; describe as `<userdata>`, never traverse |

- Probes are side-effect free and wrapped in `pcall`, because some userdata types **raise on absent field access**.
- The comment records that testing for an `IsA` method failed: UE4SS exposes `IsA` through a metatable `__index` **function**, so
  `obj.IsA` reads nil even on valid UObjects. `pcall(function() return val:GetClass() end)` is the reliable probe.
- `safety.guard(fn, ...)` is the single chokepoint for any UE call: returns `(true, result)` or `(false, err)`.
- Policy: new crash classes are fixed by adding a rule here, never at call sites.

## Local player in multiplayer (`feature_net.lua`)

`IsPlayerControlled()` is true for **any human-driven pawn**, local or remote, so a `FindAllOf` loop using it can return another
player's controller and make every command target them. Use `APlayerController:IsLocalController()`. Public API:
`local_controller()`, `local_pawn()`, plus roster helpers. Every command is routed to the local player only; the Multi tab is a
passive roster viewer.

## Hotkeys (`feature_hotkeys.lua`, `feature_wheel_hook.lua`)

- User-authored "kits" and "folders" in JSON under `ipc/`; each can have a hotkey (key plus modifiers LEFT_CONTROL, LEFT_SHIFT,
  LEFT_ALT) registered with `RegisterKeyBindAsync(key, { mods }, cb)` (modifier table optional).
- Key names resolved from UE4SS's `Key` table with aliases for mouse buttons (`LEFT_MOUSE_BUTTON` -> `LeftMouseButton`, ...).
- **No unregister exists**, so a `_generation` counter increments on every reload and each callback captures `my_gen`:
  `if _generation ~= my_gen then return end`.
- Folder modes: `set` fires every row; `toggle` alternates on and off values (a blank off value skips that row). A kit hotkey gates
  its folders; sub-kits inherit parent gates and cascade-disarm.
- **Mouse wheel:** `RegisterHook` on `PlayerController:InputAxis` **fails** because that is a native function, not a UFunction.
  Instead a gated loop (about 16 ms, only while a wheel binding exists) calls `pc:WasInputKeyJustPressed(MouseScrollUp/Down)` and
  `IsInputKeyDown` for modifiers. Cost "well under 0.1% CPU".
- A reminder from the stability article: other authors report `RegisterKeyBind` callbacks crashing under key spam (see rule 15).
  RSDWTools uses the `Async` variant throughout. Not tested here.

## Inventory and recipes (`feature_inventory.lua`)

Resolves an asset short name (`ITEM_Armour_T2_Body_Linen`, `RECIPE_Ammo_Arrows_Bone_Bleed`):
1. `FindFirstOf(name)` (a CDO or live object).
2. `AssetRegistry:GetAssetsByClass({ItemData, RecipeData})` sweep, cached `asset_name -> package_name`, subclasses included.
   Invalidated lazily: on a miss, re-sweep once.
3. `LoadAsset(package)` then `StaticFindObject(package.."."..name)`.

Verbs: `world.items.give <name> [count]`, `world.recipes.unlock <name>`. Skills use the same resolution
(`USkillData`), then `comp.Skills[i].CurrentXP`, then `SkillPerkComponent:HandleSkillLevelIncreased` after a level change.

## Gameplay effects and attributes (`feature_ge.lua`, `feature_attr.lua`)

See [reference/game-api-catalogue.md](../reference/game-api-catalogue.md). Effects: `InstantiateGameplayEffect(DataClass, InstigatingGE,
bForceNewInstance)` then `ApplyGameplayEffect(Instigator, Source, Handle, bIgnoreChanceToApply)` then `RemoveGameplayEffect`.
Attributes: write `AttributeValues[i]` / `SharedAttributeValues[i]` on `UDominionAttributesComponent`, where slot `i` is identified by
the **runtime class name** of `FloatAttributes[i]` (`UMaxStaminaAttribute`, `..._C`).

## Generic field writer and reach specs (`feature_field.lua`, `feature_probe.lua`)

One verb family can read or write any property reachable from a root:

```text
player.field.set        <reachSpec> <fieldPath> <value>
player.field.set_index  <reachSpec> <containerPath> <index> <value>
player.field.set_key | set_object | add | remove | clear | call
reachSpec  :=  <rootKey>[.<step>...]   |   subsystem:<ClassShortName>[.<step>...]
roots      :=  pawn (GameplayStatics:GetPlayerPawn(0)), ...
probe.resolve <reachSpec>        probe.read <reachSpec> <fieldPath>
```

Writes are coerced from text (bool, number, string). `world.foreach <ClassName> set|call|clear ...` applies one mutation to every live
instance of a class (`$it` token stands for the iteration target).

## Introspection (`feature_introspect.lua`, 1,784 lines)

Scan then Inspect drilldown: for an actor, emits `class_chain` and, per class in the chain from the runtime class up to `UObject`, the
`fields` (name, type, value, readable) and `methods` (name, signature). Output feeds the desktop app. `dump.types` regenerates UE4SS Lua
type stubs for the catalog pipeline.

## Other techniques worth knowing

| Feature | How |
|---|---|
| Console commands from Lua | `KismetSystemLibrary:ExecuteConsoleCommand` works; bare `PlayerController:ConsoleCommand` traps ("UObject instance is nullptr", not a UFunction) |
| List every CVar | engine commands `Help`, `DumpConsoleCommands`, `DumpConsoleVariables` through the above |
| Unlock all world options | set every loaded `UDifficultySettingData.PlayerAdjustable = 3` and `bCanBeChangedAfterWorldCreation = true`; also patch `USettingsTooltipContent` |
| Grab and move an actor with the camera | one self-terminating `LoopAsync` loop, `GetPlayerViewPoint` for the view, pre-allocated tables reused to avoid GC in the hot path; abort loudly instead of trying fallbacks |
| NPC driving | steer through AI movement and action surfaces, never `PlayerController:Possess` |
| Debug camera | `UCheatManager.ToggleDebugCamera`; their older freecam was "unstable" |
| World events | `AWorldEventManager:GetWorldEventManagerInstance(...)`, `StartEvent(TSoftClassPtr<AWorldEvent>, FTransform, players, FGameplayTag)`, confirm-gated |
| Quest IDs | saves store `QuestData.PersistenceID`; a dump maps IDs to assets for offline audits |
| Transmog | visual-only: mesh and material swaps, no inventory or `UItemData` writes |
| Save-resident world objects | small wrappers around `SaveGame` surfaces on placed objects (`feature_persistence`), `AWorldProgressManager` fields (`feature_progress`) |
| SPUD (the save system) | experimental access to its global-object registration hooks (`feature_spud`) |
| Toast | transient text driven by rows of kind `umg`; replaces the earlier persistent Insert overlay |

## Gear swap (`feature_gear_swap.lua`)

Existing-item-only presets. Selection mode tints inventory slots; "middle-click" toggles items while selection is active; scanning of inventory
widgets runs **only** in selection mode and is removed afterwards. Apply uses the normal inventory-use/server RPC path (not `domEquipItem`),
dispatches changed slots as a batch at about 70 ms cadence, then verifies the full target twice. No rollback batch during combat; a partial result
is left as is and the key can be pressed again. A toast says "server replication verified" on success. Compare with the Hot Swap module's `rlm_swaps.lua`.

## Cautions

- Treat as a map of what exists, not a recipe: much of it is experimental probes ("Round N" notes in comments).
- The exact UFunction names and field names are in its source and in `json/BPData.json` (about 2.4 MB). Grep there before probing.
- Because it drives gameplay values heavily, running it alongside mods that edit the same fields will fight (see the vanilla-first pattern in
  [FishingSliders.md](FishingSliders.md)).
