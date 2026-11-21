---
name: rsdw-mod-development
description: "Write or change any UE4SS Lua code that touches Dragonwilds game objects, UI, input, hooks, maps, items, saves or Mod Menu, in RSDWModManager or a new mod. Routes to the task-based guides in Docs/KnowledgeBase and enforces the crash rules, evidence gates and licence gate. Use before writing code that calls the game; not needed for edits that touch no game API."
---

# RSDW Mod Development

Development here is agent-only: no human reviews a change before it runs in a live game, and you cannot run the game yourself. The gates below stand in for review. Treat them as blocking.

Knowledge lives in `Docs/KnowledgeBase/` (relative to the project root). It is organised by task, not by mod.

## Load protocol (keep context small)

1. Read this file completely.
2. Read `Docs/KnowledgeBase/reference/stability-rules.md` completely before writing any code that touches the engine. It is short and every rule was paid for by a crash.
3. Read **only** the guides your task needs, from the routing table. Do not read the whole knowledge base.
4. To find a class, function or field name, grep `reference/game-api-catalogue.md` first. For UE4SS API signatures read `reference/ue4ss.md`, then the matching page of the official UE4SS Lua API documentation (one page per function or class) before calling an API you have not used before.
5. Open a `sources/` note only when a guide's "Seen in" line points there and you need the technique in its full original context.

## Routing table (guide, approximate size)

| Task | Read |
|---|---|
| New mod, files, loading, config parsing, packaging | `guides/mod-anatomy.md` (5 KB) |
| Where code runs, loops, timers, world changes, reload | `guides/execution-model.md` (6 KB) |
| React to a game event | `guides/hooks-and-events.md` (7 KB) |
| Get the player, a component, a widget, an asset | `guides/finding-objects.md` (6 KB) |
| Read or write fields, arrays, maps, text, out params | `guides/reading-writing-values.md` (7 KB) |
| Keys, mouse, controller, input modes | `guides/input.md` (7 KB) |
| Build windows, text, images | `guides/ui-construction.md` (7 KB) |
| Pause menu, HUD changes, docking, list tiles, notifications | `guides/extending-game-ui.md` (8 KB) |
| Pins, map icons, minimap | `guides/map-and-minimap.md` (11 KB) |
| Spawn or move actors, effects, assets | `guides/actors-and-world.md` (7 KB) |
| Change game numbers | `guides/tuning-game-data.md` (5 KB) |
| Health, quests, items, skills, unlocks, targets, saves | `guides/reading-game-state.md` (8 KB) |
| Grant, find, equip, swap items | `guides/inventory-and-equipment.md` (4 KB) |
| Save files, config, Mod Menu, other mods | `guides/persistence-and-config.md` (7 KB) |
| A scan, many objects, anything per frame | `guides/performance.md` (5 KB) |
| Probe, log, test, crash investigation | `guides/diagnostics-and-testing.md` (5 KB) |
| Co-op, host, remote players | `guides/multiplayer.md` (4 KB) |
| Pak content, Blueprint loader, native code | `guides/native-and-paks.md` (4 KB) |
| What UE4SS provides, API seen in use, known build bugs | `reference/ue4ss.md` (12 KB) |

If a task spans guides, read each. If no guide covers it, say so and treat the work as a probe (see evidence gates).

## Hard rules (summary; reasons are in stability-rules)

1. Run everything on the game thread (`LoopInGameThreadWithDelay`, `ExecuteInGameThread`). No `LoopAsync` logic. Never start a UE4SS timer inside a timer callback.
2. Hook and key callbacks **record only**; the next tick does the work. Register each hook once; retry arming; wrap in `pcall`. `RegisterKeyBind` callbacks run on a **different thread** from the game thread (measured on our build): never touch a UObject, widget or shared table in one, only a flag; prefer polling on the game thread.
3. Never `FindAllOf` or `FindFirstOf` per tick (35-60 ms each). Use intervals, triggers and caches.
4. Call `IsValid()` immediately before every use of a stored object. Never call anything on an empty object field. Never hold a handle across a world change: drop it without touching it.
5. Never read a soft object reference from Lua. The installed UE4SS build (`f6d5f942`, build 1135) crashes on it. Use a precomputed path table and load by full path. Upstream fixed this at builds 1172-1174 and 1190/1213; do not assume our loader has it until a dated test says so.
6. Never read all properties of an object; read named fields only.
7. Do not treat FText, FName, FString, structs or soft refs as UObjects.
8. Do not call `ClearPin`, `SetHoveredMapIcon` + `TryRemoveHoveredMapIcon`, `ItemsToDrop` or `DropItemFromInventory` from Lua.
9. Build UI once per world, then show, hide and rewrite. Never rebuild rows on open. Use a new unique name for every constructed object. Pool widgets and cap pools.
10. Do not remove or destroy a game widget you replace; make it invisible or move it, and restore pooled widgets before dropping them.
11. Tune game values vanilla-first: store the original once, derive from it, restore on disable, write nothing at defaults, read back after writing.
12. Never write the game's save. User data goes under `%LOCALAPPDATA%` (ours: `%LOCALAPPDATA%\RSDWModManager`) with atomic writes.
13. Use `IsLocalController()` for "the local player", `HasAuthority()` for host. Do not use `IsPlayerControlled()`.
14. Keep `cfg`, `config.txt`, `modmenu.json` and the live-keys list in step.
15. Treat `pcall` as incapable of catching native crashes: prevent the call, do not rely on catching it.

## Precedence

- This repository's own rules win: PC-only, standalone Mod Manager, the `rsdw-mod-manager-ui` skill, `README.md` safety boundary. The guides describe controller input for other mods; **do not implement controller navigation for the Mod Manager** unless the user changes scope.
- Guides record other authors' findings on their builds. A log from our installed build outranks a guide: if they disagree, trust the log and edit the guide.
- `Docs/TEST_PLAN.md` unchecked means unproven.

## Evidence gates

- Every technique carries a confidence label in the guides: Measured (by its author), Observed in code, Unverified here. None is proven on our build until a dated entry says so.
- If your change depends on game behaviour no guide marks as measured, or on an API the guides do not list, ship it first as an **opt-in one-shot probe** behind a config flag: named fields only, log each step, no side effects from hooks. State plainly in `HANDOFF.md` that the user must run it. Do not build the feature on the unverified assumption.
- You cannot confirm gameplay yourself. Static checks (`luaparse`, JSON validation) prove syntax only. Never tick a TEST_PLAN checkbox from them.
- Crash or hang: read `ue4ss/UE4SS.log` and `%LOCALAPPDATA%/RSDragonwilds/Saved/Logs/RSDragonwilds.log`; a native failure may leave no Lua error.

## Licence gate

- Copy code only from Starfall (MIT) or RuneSchema's own original code (MIT, scope limited by its `LICENSING.md`), and only with the copyright and permission notice carried along and recorded in a `THIRD_PARTY_NOTICES` entry. Full table: `Docs/KnowledgeBase/README.md`.
- Every other reference or installed mod (including RSDWTools, QuestLog, CollectionLog, EnemyHPNumbers) has no licence file: learn the technique, write your own implementation, do not paste source.
- Third-party mods are never `require`d, loaded, executed or depended on at runtime, and their DLLs are never loaded.
- Other authors' mods are not prototypes of this project.

## Known loader issues

- `reference/ue4ss.md` maps the installed UE4SS build (1135) against upstream fixes. Do not swap the loader as part of a feature change; it is the user's decision and needs a backup and a native-mod test.
- Measured on build 1135: the delayed-action API and thread-id functions exist; key-bind callbacks run off the game thread; out-parameter tables leak registry references (about 2 slots per call) and put all out values in the first table.
- No pak authoring pipeline.

## Before you finish (self-review checklist)

Answer each in your handoff, briefly.

1. Which hard rules does this diff touch, and how is each satisfied?
2. Hooks: record-only, armed once, retried?
3. Scans: interval or trigger, cached, one sweep for many items?
4. Stored objects: validated before use, cleared on world change?
5. Writes to game values: original stored, restored, read back?
6. Persistence: atomic, outside the game save, bounded reads?
7. Config: four lists in step?
8. Files changed parse (`npx --yes luaparse <file>`, `ConvertFrom-Json`)?
9. README, ROADMAP and TEST_PLAN updated; HANDOFF separates static validation from live results?
10. New knowledge recorded in the guide for the capability it enables, with date and confidence label?

## Extending the knowledge base

- Put a finding in the guide for what it lets someone do, not in a per-mod note. Include the call, the pitfall, the source (mod and file, or our own test and date) and a confidence label.
- Edit a contradicted entry; do not append a second one.
- Add a `sources/` note only for a mod new to the library. Record its licence status in `Docs/KnowledgeBase/README.md`.
- Keep guides tight: calls, steps, numbers, pitfalls. No narrative.
