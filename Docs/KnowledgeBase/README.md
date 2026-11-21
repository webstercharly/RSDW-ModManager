# Mod development knowledge base

Developer documentation for building Dragonwilds mods on UE4SS, organised **by what you need to do**. It
was built from how existing mods use the functionality; the mods are cited as evidence, not described for
their own sake.

**Agents: enter through `.agent/skills/rsdw-mod-development/SKILL.md`.** It gives the load protocol (read
`reference/stability-rules.md`, then only the guides your task needs), the hard rules, evidence and licence
gates, and a self-review checklist. Do not read this whole tree.

## Find what you need

| I want to... | Read |
|---|---|
| Start a mod, lay out files, load and ship it | [guides/mod-anatomy.md](guides/mod-anatomy.md) |
| Decide where code runs; loops, timers, world changes | [guides/execution-model.md](guides/execution-model.md) |
| React to something the game does | [guides/hooks-and-events.md](guides/hooks-and-events.md) |
| Get a reference to a player, component, widget or asset | [guides/finding-objects.md](guides/finding-objects.md) |
| Read or write fields, arrays, maps, text; avoid unsafe values | [guides/reading-writing-values.md](guides/reading-writing-values.md) |
| Handle keys, mouse, controller, input modes | [guides/input.md](guides/input.md) |
| Build my own windows, text, images, panels | [guides/ui-construction.md](guides/ui-construction.md) |
| Add to or restyle the game's UI (pause menu, HUD, skills screen) | [guides/extending-game-ui.md](guides/extending-game-ui.md) |
| Work with the map, pins, map icons, or build a minimap | [guides/map-and-minimap.md](guides/map-and-minimap.md) |
| Spawn, move and clean up actors and effects | [guides/actors-and-world.md](guides/actors-and-world.md) |
| Change game numbers safely | [guides/tuning-game-data.md](guides/tuning-game-data.md) |
| Read health, quests, items, skills, unlocks, targets, saves | [guides/reading-game-state.md](guides/reading-game-state.md) |
| Grant, find, equip or swap items | [guides/inventory-and-equipment.md](guides/inventory-and-equipment.md) |
| Save data, read config, add Mod Menu settings, talk to other mods | [guides/persistence-and-config.md](guides/persistence-and-config.md) |
| Keep a feature fast | [guides/performance.md](guides/performance.md) |
| Investigate, log, probe and test | [guides/diagnostics-and-testing.md](guides/diagnostics-and-testing.md) |
| Behave correctly in co-op | [guides/multiplayer.md](guides/multiplayer.md) |
| Ship own models, Blueprint logic or native code | [guides/native-and-paks.md](guides/native-and-paks.md) |

Each guide has the same shape: when to use it, the calls and steps, pitfalls, and where it was seen.

## Reference

| File | Contents |
|---|---|
| [reference/stability-rules.md](reference/stability-rules.md) | Every crash the other mods paid for, as rules. Read before touching the engine |
| [reference/game-api-catalogue.md](reference/game-api-catalogue.md) | Hook targets, classes, functions and fields seen in use |
| [reference/ue4ss.md](reference/ue4ss.md) | UE4SS API digest from the official docs, our build against upstream history (which fixes we lack), settings, remaining gaps. Full docs: `References/UE4SS/Docs/upstream-v4.0.0/` |

Also: `Tools/Probes/UE4SSProbe/` is an inert, ready-to-run probe that measures the open UE4SS questions on our installed build (threads, key binds, out-param leak, soft reads, nested timers). A user runs it; its README says which guide entry each result updates.

## Evidence: how specific mods did it (`sources/`)

Per-mod notes the guides draw on. Use them to see a technique in full context or to follow a source file.

| Note | Mod | Mainly evidence for |
|---|---|---|
| [AurelianUI-Minimap](sources/AurelianUI-Minimap.md) | AurelianUI HUD Overhaul 2.0 | minimap, overlay canvas, textures, masks |
| [ResourceAtlas-and-PenguinFinder](sources/ResourceAtlas-and-PenguinFinder.md) | ResourceAtlas 1.5, PenguinFinder 3 | map icon cost and pooling, pin override |
| [MapMarkers](sources/MapMarkers.md) | Custom Map Markers 1.0.0 | pin internals, key sampler |
| [NoAutoPickup](sources/NoAutoPickup.md) | NoAutoPickup 1.1.0 | value override, object identification |
| [AutoTool](sources/AutoTool.md) | AutoTool 1.0.3 | facing detection, item choice, themed popup |
| [FishingSliders](sources/FishingSliders.md) | FishingSliders 1.1.2 | tuning data, input injection |
| [Slayer](sources/Slayer.md) | Slayer 1.1.2 | hooks, skills tile, pause menu |
| [SkillPets](sources/SkillPets.md) | Skill Pets 1.0.1 | local actors, paks, registry leak |
| [Starfall](sources/Starfall.md) | Starfall 0.9.0 (MIT) | architecture, spawn, notify |
| [RuneSchema-and-ModMenu](sources/RuneSchema-and-ModMenu.md) | RuneSchema 0.9.0.1 | Mod Menu protocol, plugin loader |
| [ClassSpecialisations](sources/ClassSpecialisations.md) | Class Specialisations 0.9.6 | Lua + native bridge (survey level) |
| [RSDWTools](sources/RSDWTools.md) | RSDWTools (installed, other author) | safety classifier, hotkeys, API map |
| [QuestLog](sources/QuestLog.md) | QuestLog 1.4.3 (installed) | pause menu, pad input, docking, quests |
| [CollectionLog](sources/CollectionLog.md) | CollectionLog 2.2 (installed) | soft-reference crash, catalogs |
| [EnemyHPNumbers](sources/EnemyHPNumbers.md) | EnemyHPNumbers 1.3.2 (installed) | real health, pooled widgets |

MiniMap 1.0.7 is a compiled DLL with no source, so there is no note for it.

Note for this copy: the `References/` and `Tools/` folders mentioned throughout these notes are not included. Those paths are provenance only; nothing here depends on them.

Mods are in two places: `References/OnlineMods/` (downloaded archives, with hashes in `References/catalog.json`) and the live
`ue4ss/Mods/` folder (RSDWTools, QuestLog, CollectionLog, EnemyHPNumbers, read in place).

## Licences: what can be reused

Checked on 2026-11-20 by searching every reference and installed mod for licence files:

| Source | Licence found | What it lets us do |
|---|---|---|
| Starfall 0.9.0 | `LICENSE.txt`: MIT, Copyright 2026 Starlove | Copy, modify, redistribute, including commercially, **if the copyright and permission notice are kept** in the copies |
| RuneSchema 0.9.0.1 | `Helpy/licenses/LICENSE`: MIT, Copyright 2026 RSDW Modding Community, scoped by `LICENSING.md` | Same, **only for the original RuneSchema software, docs, schemas and examples the community owns**. Third-party parts keep their own licences (`THIRD_PARTY_NOTICES.md`: PalSchema MIT, Dear ImGui MIT, nlohmann JSON MIT). Art, game data, Jagex and Epic material are **not** covered. Its native DLLs are unaudited |
| UE4SS (the loader) | `ue4ss/LICENSE`: MIT, Copyright 2022 Narknon | Same, for UE4SS itself. Applies to the loader, not to mods that run on it |
| AurelianUI, MiniMap, MapMarkers, PenguinFinder, ResourceAtlas, NoAutoPickup, AutoTool, FishingSliders, Slayer, SkillPets, Class Specialisations | **none found** | Treat as all rights reserved. Learn, do not copy. (Class Specialisations ships only `MinHook-LICENSE.txt` and `UE4SS-LICENSE.txt` for components inside it.) AurelianUI's README says its HUD widget names come from Relic Hunter UI "used with his permission" |
| QuestLog, CollectionLog, EnemyHPNumbers, RSDWTools | **none found** | Same: learn, do not copy |

Practical rules:
- When copying MIT code, keep the copyright line and the permission text with it (a comment block at the top of the file and an entry in a `THIRD_PARTY_NOTICES` file).
- A missing licence file is not a grant. For code we want from an unlicensed mod, ask the author.
- Game art, textures and text belong to Jagex or the mod author whatever the code licence says.
- Snippets in the guides are short paraphrases or call sequences, not copied source.
- This is a plain reading of the files, not legal advice.

## Confidence labels

- **Measured**: the author says they tested it in game. We have not reproduced it unless a line says so.
- **Observed in code**: seen in source, no stated test.
- **Unverified here**: nothing in this project has confirmed it on our build. Check against `UE4SS.log`.

The mods target Dragonwilds 1.0 and UE4SS builds around `f6d5f942`, which is our installed loader. Game paths and class names can
move in an update.

## Adding to this

Write by functionality: put a new finding in the guide for what it lets you do, with the call, the pitfall, and which mod or which of our own
tests showed it, with a date. If it contradicts an entry, edit the entry. Add a source note only when a mod is new to the library.
