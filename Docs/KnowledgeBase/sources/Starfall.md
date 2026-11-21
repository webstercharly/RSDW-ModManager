# Starfall 0.9.0: implementation guide

Source: `References/OnlineMods/Starfall/0.9.0/extracted/Starfall/Scripts/` (about 6,700 lines, 37 files).
Author Bruce Starlove. **MIT licence** (`LICENSE.txt`): code may be reused with the copyright notice kept.
Its README mentions a `DISCOVERY.md` that is not in the archive.

**What it does:** shooting stars land at set sites, the host spawns a layered ore rock, players mine it,
get Stardust, and a Star Sprite appears with a shop.

**Why read it:** the cleanest architecture here, and the only reference that spawns actors, adds map icons,
shows notifications, and shares game-owned behaviour (mining, drops, XP) without re-implementing it.

## File layout

```text
main.lua / boot.lua     wiring; boot.start() runs again on reload
ss.lua                  runtime: log, paths, try(), timers pump, hook trampolines, reload
core/*.lua              pure logic, no engine calls: director, sites, layers, rewards, shop, purse,
                        titles, persist, config, base64, pictures
game/*.lua              engine glue: controller, star, landing, marker, notify, payout, vendor, fx,
                        assets, world
art/*.lua               PNG art stored as base64 text modules
lib/json.lua            JSON
```

Rule: `core` never touches UE objects; `game` is the only layer that does. The director (state machine)
emits events and `game/controller.lua` turns them into actors and messages.

## Runtime (`ss.lua`)

- **Idempotent file.** State lives in one global table `Starfall`; running the file again only redefines
  functions. Safe for reload.
- **Timer pump.** One UE4SS timer (`LoopInGameThreadWithDelay(15, pump)`) runs a table of named loops and
  one-shot "after" entries. Reason: starting a UE4SS timer inside a timer callback crashed.
  `ExecuteInGameThread(function() LoopInGameThreadWithDelay(...) end)` is used to start it, since that queue
  is separate. API: `SS.loop(name, ms, fn)`, `SS.after(ms, fn)`, `SS.stopLoop(name)`. Naming a loop replaces the
  previous one with that name.
- **Hook trampoline.** `SS.hook(path, name, handler)` registers the real `RegisterHook` once per path and
  dispatches to a table of named handlers. Handlers can be replaced on reload. Returns `false, err` if the
  function does not exist yet (a Blueprint not loaded), so the caller retries later. Return values of handlers
  go back to UE4SS and **overwrite the hooked function's return value**: a handler that only watches must
  return nothing.
- **Guarded call.** `SS.try(label, fn, ...)` runs in `pcall`, counts errors per label (`_errorCounts`).
- **Reload.** Installs a module searcher at `package.searchers[1]` that loads reloadable modules
  (`boot`, `core.*`, `game.*`, `dev.*`, `lib.*`) from disk with `loadfile`, because "UE4SS installs a module
  searcher that keeps compiled files in memory, so clearing `package.loaded` and calling `require` again would
  re-run stale code". `SS.reload()` reloads `ss.lua`, clears `package.loaded` for those patterns, restarts.
- **Dev gating.** `dev/` exists only in dev builds; it loads only if `dev_enabled.txt` exists.
- **Console command:** `SS.command("star", fn)` is registered once and dispatches through a table.

## Spawning a world actor (`game/world.lua`)

```lua
local actor = world:SpawnActor(class, {X=x,Y=y,Z=z}, {Pitch=0, Yaw=yaw, Roll=0})
local tags = actor.Tags; tags[#tags+1] = FName("Starfall")          -- tag every actor the mod owns
actor:K2_DestroyActor()
-- cleanup after a reload or crash: for each owned class FindAllOf(name), keep those where actor:ActorHasTag(tag)
```

- Tagging makes cleanup safe after reloads: `destroyTagged()` removes only actors with the mod's tag, scanning
  an explicit list of owned classes (`DivineRock`, `TargetPoint`, `BP_BaseInteractableNPC_C`, `PointLight`).
- Players: `World.players()` lists controllers/pawns; `localFeet()` uses
  `pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()` and `pawn:GetActorForwardVector()`.
- Compare actors by `GetAddress()`.

## Reusing a game actor for new behaviour (`game/star.lua`)

The star is the game's own **Divine Rock** from the Divine Rock spell
(`/Game/Gameplay/UtilityMagic/PerkSpells/DivineRock/Types/...`). Using it means mining, pickaxe gating, drops, XP
and the break burst are all the game's. The mod only:

1. spawns it, `actor.bSkipSpudStore = true` (keep it out of the world save),
2. `SetActorScale3D`, lifts it by `22 * scale`,
3. "settle": `actor["Hover ZScale"] = 0`, `actor.RotatingMovementComponentStable:Deactivate()`, hide the gold
   swirl `actor.NS_DivineRock_Loop:SetVisibility(false, true)` + `Deactivate()`,
4. sets health: `actor.HealthComponent:ModifyMaxHealth(h)` and `:SetHealth(v, "Starfall")`,
5. renames only its own rock by hooking
   `BP_DivineRockBase_C:GetDisplayName` and returning `FText(...)` when `context:get():GetAddress()` matches.
   The hook can only be set after the Blueprint is loaded, so it is retried each time a rock is placed.

Observation without hooks: polls `actor.HealthComponent:GetAuthoritativeHealth()` and `actor:GetState()`
(`EDivineRockState`, 2 = destroying) plus `actor:GetDestroyReason()` (`1` expired, `2` mined). Attribution of
damage to players uses one hook, `PlayerMeleeAttackComponent:Multicast_SendDamageCacheData`, that only records
`lastSwing[playerId] = os.clock()`; the poll splits health loss among swingers within 1.5 s.

Gotcha from the code comment: "the game removes a rock that stands where the world has not loaded yet" (a rock
placed 163 m from the player vanished after 8 s). The rock exists only while a player is close.

## Map marker without touching map code (`game/marker.lua`)

```lua
actor = World.spawn(TargetPoint class, x, y, z, 0)                  -- "an engine actor with a position and nothing else"
icon  = actor:AddComponentByClass(MapIconComponent class, false, NO_OFFSET, false)
icon:SetIconTexture(picture)                                        -- our own texture, see below
icon:SetIconSize(50, 0)                                             -- 50 screen units (unit 0)
icon:SetIconTooltipText(FText(name))
icon:SetIconFogInteraction(3)                                       -- EIconFogInteraction::AlwaysRenderAboveFog
icon:SetIconZOrder(4)
icon:SetIconVisible(true)
```

Spawned on this machine only, so only this player's map shows it. `NO_OFFSET` is a transform table
`{Rotation={X=0,Y=0,Z=0,W=1}, Translation={...}, Scale3D={X=1,Y=1,Z=1}}`. This is the same component
MapMarkers re-icons, and a simple way to add our own map pins from a module.

## Loading pictures without a pak (`game/assets.lua`)

```lua
library = Default__KismetRenderingLibrary
tex = library:ImportFileAsTexture2D(context, path)     -- context = any live world object
```

- "Something has to hold the texture (a widget, a map icon) or the game frees it", so the next call re-reads the
  file.
- Pictures ship as base64 text in `art/*.lua`; `Pictures.restore` writes the PNG into the mod folder on first use.
- Same technique as AurelianUI's `texture()`.

## Asset slots with fallbacks (`game/assets.lua`)

`Assets.slots[name] = { candidate1, candidate2, ... }`. `Assets.resolve(slot)` loads candidates in order until one
loads, caches the result, logs which path won, and `Assets.check()` reports empty slots at startup so a game
patch that moves an asset shows as one log line. `Assets.load(path)`: `StaticFindObject`, else `LoadAsset(path)`,
else for a Blueprint class strip `_C`, `LoadAsset(package)` and look again. Asset folders used include
`/Game/Art/VFX/Library/`, `/Game/Audio/MetasoundSources/`, `/Game/Gameplay/Items/Resources/`,
`/Game/Gameplay/Items/Consumables/Magic/`, `/Game/Gameplay/NPCs/BP_BaseInteractableNPC`,
`/Game/Gameplay/World/Vendors/DT_VendorDataTable`, `/Game/Gameplay/Progress/XPEventTables/DT_XPEvents_Mining`.
Camera shake classes under `/Game/Gameplay/AI/DragonVelgar/` are reused for the landing impact.

## Notifications to players (`game/notify.lua`)

```lua
controller:Client_DisplayTextNotification({ TagName = FName("UI.Notification.Event.Velgar.AttackMeteors") }, FText(text))
```

- The game's own dark band at the top of the screen, used for world events.
- The gameplay tag only chooses the style/slot; the text shown is always yours.
- The call replicates to the owning client, so in co-op players see it **whether or not they have the mod**.
- The game shows one at a time for about 2.4 s each; the mod queues text until the band is free.
- Range filter: send to every player controller (`player.pawn.Controller`) within a radius.

## Persistence

`core/persist.lua`: temp file then rename, `.tmp` recovery, `.corrupt` quarantine, file access injected for tests.
Saved after every change. See [guides/persistence-and-config.md](../guides/persistence-and-config.md).

## Host authority

Everything runs on the host only. Vendor and shop UI use the game's vendor data table; payouts and Stardust are
tracked per player id in a purse and saved with the mod's own file.

## Reusable recipes

| Need | Take this (MIT: copy with notice) |
|---|---|
| Crash-safe timers | `ss.lua` pump |
| Re-registerable hooks | `SS.hook` trampoline |
| Hot reload of modules | `freshSearcher` plus `_restart` |
| Spawn, tag, clean up actors | `world.lua` |
| Add a map pin from code | `marker.lua` |
| Ship PNG art as text | `art/*.lua` + `pictures.lua` + `ImportFileAsTexture2D` |
| Fallback asset paths | `Assets.slots` / `resolve` / `check` |
| On-screen text for all players | `Client_DisplayTextNotification` |
| Atomic save | `core/persist.lua` |

## Cautions

- Written against Dragonwilds 1.0; asset paths may move. `Assets.check()` exists for that reason.
- Spawned actors are not saved with the world (`bSkipSpudStore`), so the mod must recreate them on load.
