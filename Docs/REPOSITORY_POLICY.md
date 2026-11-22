# Repository policy

Each independently installable module belongs in its own repository. The
manager shell stays free of module-specific gameplay code.

## Public by default

A module can be public when its normal purpose is presentation, observation or
quality-of-life behaviour that follows ordinary game interactions:

| Module family | Visibility | Boundary |
|---|---|---|
| Manager shell | Public | Module discovery, lifecycle, UI and shared services only. |
| Map and Preview | Public | Observation and presentation only. |
| Hot Swap | Public | User-triggered equipment changes through bounded, normal inventory paths. |
| MCP | Public | Read-only diagnostics with explicit tools; no generic execution. |
| Loot information | Public | Search, tables and odds only. |

## Private when it cheats or automates play

Keep a module private when it bypasses progression, creates game state, removes
combat constraints or performs gameplay on the player's behalf:

| Module family | Visibility | Reason |
|---|---|---|
| Cheats and cooldown changes | Private | Directly alters game rules or protected values. |
| Item or creature spawning | Private | Creates game state outside ordinary play. |
| Loadout deficit restoration | Private | May generate missing equipment; a non-generating loadout can be separated later. |
| Teleport, chest interaction and gathering | Private | Moves or interacts for the player. |
| Combat, boss helpers and Auto Eat | Private | Automates survival or combat. |
| MCP action providers | Private | Changes game state through a separate server and mailbox. |

Mixed modules must be split at the capability boundary. A public reader must
not dynamically discover, import or advertise private actions. A private action
provider may repeat the minimum observation it needs, but it does not turn the
public MCP into a plugin host for game-writing code.

Visibility is reviewed per capability, not merely per menu name. If a public
module later gains a cheat feature, that feature moves to a private repository.
