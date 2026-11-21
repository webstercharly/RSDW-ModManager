# Guide: hooks and events

**Use this when** you need to react to something the game does.

## Decide first: do you need a hook?

Polling a value is safer than hooking. FishingSliders took four UE4SS crashes from fishing hooks and now has none; AutoTool has none. Prefer a hook only when:
- the event is rare and not observable from state (a creature dying, an NPC talked to, a map opening),
- polling would be expensive.

If you hook, **record in the callback and do the work on the next tick** (the same rule every mod follows).

## RegisterHook

```lua
local pre, post = RegisterHook("/Script/Dominion.PlayerInteractionManager:Multicast_AcknowledgeInteractionRequest",
  function(self, comp)                -- pre: before the function runs
     local owner = comp:get():GetOwner():GetFullName()
     queue[#queue+1] = owner          -- RECORD ONLY
  end,
  function(self, ...) end)            -- post (optional)
UnregisterHook(path, pre, post)       -- exists (bundled mods use it)
```

- **Path forms:** `/Script/<Module>.<Class>:<Function>` for native classes, `/Game/.../<Asset>.<Asset>_C:<Function>` for Blueprints.
- **Timing depends on the path (official docs).** For a `/Script/` path the first callback runs **before** the function and the optional second one after. For any other path (Blueprint functions) the first callback runs **after** the function and the second does nothing. So a Blueprint hook cannot change what the function sees.
- **Parameters are wrappers** (`RemoteUnrealParam`): `self:get()` is the object, `param:get()` the value, **`param:set(v)` changes it** (a pre-hook can alter an argument), `param:type()` names the type. They have no `IsValid()` or `GetAddress()`. Use `pcall` around reads.
- Returns two ids; keep both for `UnregisterHook(path, preId, postId)`.
- The callback is **not guaranteed to run on the game thread**: it runs where the engine calls the function. Check with `IsInGameThread()` or compare `GetCurrentThreadId()` to `GetGameThreadId()` before assuming. Measured on our build (2026-11-20): `NotifyOnNewObject(PlayerController)` and a `/Script/` hook on `PlayerController:ClientRestart` both ran on the game thread.
- **Only UFunctions can be hooked.** `PlayerController:InputAxis` is native and `RegisterHook` fails ("no UFunction with the specified name was found"), so RSDWTools polls `WasInputKeyJustPressed` for the mouse wheel instead.
- **A Blueprint function does not exist until its class is loaded.** `RegisterHook` then fails; retry (Slayer every 15 s until armed; Starfall retries each time it places a rock). Never register twice: that double-counts.
- **Return values overwrite.** The value your handler returns goes back to UE4SS and replaces the function's return. Starfall returns `FText("Fallen Star")` from `GetDisplayName` to rename one actor; a watching handler must return nothing.
- **Re-entrancy guard.** If your own code calls the hooked function (PenguinFinder calls `Client_NotifyPinsSet` itself), set an `applying` flag around the call and ignore the hook while it is set.
- **Ignore your own calls.** Slayer's Skills-screen hooks skip while `T.inCall` is true.
- Wrap handler bodies in `pcall` and copy args first: `local args = {...}; pcall(fn, table.unpack(args))` (PenguinFinder).

## Hook trampoline (so reload and retries are safe)

```lua
local H = {}                                      -- path -> { name -> handler }
function hook(path, name, fn)
  H[path] = H[path] or {}; H[path][name] = fn
  if registered[path] then return true end
  local ok, err = pcall(RegisterHook, path, function(...)
    local result
    for n, h in pairs(H[path] or {}) do
      local ran, v = pcall(h, ...)
      if ran and v ~= nil and result == nil then result = v end
    end
    return result
  end)
  if ok then registered[path] = true end
  return ok, err
end
```

(Starfall `SS.hook`, MIT.)

## NotifyOnNewObject

```lua
NotifyOnNewObject("/Script/Dominion.PauseMenuScreen", function(obj) seen[#seen+1] = obj end)   -- store only
```

- Fires when an object of that class (or subclass) is **constructed**; the callback runs inside construction, so do **one cheap thing**. MapMarkers does a single integer write (`MaxNumberOfPins`) and stores nothing, because stored handles to front-end controllers are freed at world load.
- Returning `true` unregisters it (Class Specialisations; official docs agree). The class need not exist yet. **Register one callback per class** and put all work in it: duplicates across mods "could cause performance issues ... seen in the wild" (official docs).
- Deduplicate stored objects by `o:GetAddress()`.
- Typical use: grab **screens** the game creates once (pause menu, Skills screen, inventory) instead of scanning later with `FindFirstOf` (35-50 ms).
- Caps: Slayer stores at most 20 screens.

## Other event registrations

| Call | Use |
|---|---|
| `RegisterBeginPlayPostHook(fn(contextParam))` | an actor began play (RuneSchema, bundled mods) |
| `RegisterLoadMapPostHook(fn(_, worldParam))` | map load; reset per-world state |
| `RegisterCustomEvent` | Blueprint custom events (bundled mods) |
| `RegisterConsoleCommandHandler(name, fn)` | console commands (see [diagnostics-and-testing](diagnostics-and-testing.md)) |
| `RegisterKeyBind` / `RegisterKeyBindAsync` | keys, see [input](input.md) |

## Events other mods have used (all measured by their authors)

| Event | Hook target | Notes |
|---|---|---|
| Enemy died | `/Game/Gameplay/AI/BP_DominionAICharacter.BP_DominionAICharacter_C:BP_OnDeath` | once per death; not on unload or player death. Credit via `controller.ThreatSystem.DamageInstigators:ForEach` |
| Player pressed E on something | `PlayerInteractionManager:Multicast_AcknowledgeInteractionRequest` | arg 1 is the interaction component, its owner is the NPC |
| Dialogue advanced | `ConversationParticipantComponent:ServerAdvanceConversation` | |
| Any button clicked | `/Script/CommonUI.CommonButtonBase:HandleButtonClicked` | **mouse only**, a pad never fires it ([input](input.md)) |
| Map opened or closed | `WBP_TopNav_Map_C:BP_OnMapMaximised` / `BP_OnMapMinimised` | |
| Pins changed | `MapCustomizationComponent:Client_NotifyPinsSet`, `Server_NotifyPinPlaced`, `Server_NotifyPinCleared` | |
| Quest tracked on load | `QuestProgressComponent:Client_NotifyTrackedQuestLoaded` | arrives **before** the tracker widget exists: record and replay |
| Skills screen | `Skills2MainScreen:OnIntroAnimationFinished`, `OnSkillTileSelected`, `OnSkillTileClicked`, `OnEntryWidgetCreated` | |
| Melee swing connected | `PlayerMeleeAttackComponent:Multicast_SendDamageCacheData` | Starfall records the attacker only |
| Lore popup | `LorePopupUIAPI:OpenLorePopup` | |
| Display name requested | `BP_DivineRockBase_C:GetDisplayName` | replace the return |

Full table: [reference/game-api-catalogue.md](../reference/game-api-catalogue.md).

## Hook-free alternatives that worked

| Instead of hooking | Do |
|---|---|
| a catch event | poll the spot's quantity and the player's fishing state in a half-second window (FishingSliders) |
| XP gained | read each skill's XP total once a second (SkillPets; the hook misses native XP) |
| health changed | read one drawn float (`VitalFillValue`) as a change detector ([reading-game-state](reading-game-state.md)) |
| a window opened | watch `IsShowingMap()` or widget visibility per tick (MapMarkers) |
| node drop | compare new world items to a known node position (NoAutoPickup) |

## Pitfalls

- A hook callback that does heavy work or a `FindAllOf` stalls the game thread where it fires.
- Hooking a function that fires every frame floods the callback; check what fires and how often with a counter first.
- Do not store the `self` wrapper; store `self:get():GetFullName()` or an address and re-resolve.

## Seen in

[sources/Slayer.md](../sources/Slayer.md), [sources/Starfall.md](../sources/Starfall.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/MapMarkers.md](../sources/MapMarkers.md), [sources/FishingSliders.md](../sources/FishingSliders.md).
