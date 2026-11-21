# Slayer 1.1.2: implementation guide

Source: `References/OnlineMods/Slayer/1.1.2/extracted/Slayer/Scripts/` (`main.lua` 4,051 lines plus
`skilltile.lua`, `perklist.lua`, `perks.lua`, `slayerlog.lua`, `retire.lua`, `xp.lua` and data files).
Author Maxxfilth. No licence stated: learn, do not copy.

**What it does:** kill tasks from the game's Slayer-themed NPCs, a Slayer skill (1-99), a window, a Skills-screen
tile, perks, rewards, controller support.

**Why read it:** the most complete example of **UI that lives inside the game's own screens** (pause menu,
Skills screen), **hook-to-queue** discipline, and **world-change cleanup**.

## Core discipline

1. Every hook callback only **records** into a queue (`KQ` kills, `IQ` interactions, flags tables).
2. One game-thread tick (`LoopInGameThreadWithDelay`) does all the work.
3. Nothing happens for a quiet period after load (40 s in `main.lua`'s tick).
4. Every stored object is `IsValid`-checked right before use, every call is under `pcall`.
5. Hooks are registered **once**, retried on a slow timer until the target exists.

## Hook callback shape (UE4SS)

Callbacks receive `self` (and parameters) as wrappers; use `:get()`:

```lua
local function onDeath(self)
    local s = self:get()                       -- the actor the UFunction ran on
    local cls = s:GetClass():GetFName():ToString()
    local c = s:GetController()
    c.ThreatSystem.DamageInstigators:ForEach(function(_, el) local x = el:get() ... end)   -- who damaged it
end
local function onTalk(self, comp) local c = comp:get(); n = c:GetOwner():GetFullName() end
```

- Kill signal: `BP_DominionAICharacter_C:BP_OnDeath` fires **once per creature death**, never on unload and not on the
  player's own death. Credit: a kill counts if one of the controller's `ThreatSystem.DamageInstigators` is the local
  player's pawn (matched by full name against `S.pawnNames`).
- Also read: `s.PowerLevel` (Int on `DominionAICharacter`).
- Talk signal: `PlayerInteractionManager:Multicast_AcknowledgeInteractionRequest`; argument 1 is the NPC's interaction
  component, its owner is the NPC. Only the owner's name is stored; the game's own dialogue runs untouched and the window
  opens after it closes.
- Click signal: `CommonButtonBase:HandleButtonClicked` records the clicked button's full name; rows register their
  widget name in `ROWREG`, so a click maps back to a row.
- Retry: `hookTick(now)` retries `RegisterHook` every 15 s until it works, then marks it armed (a hook registered
  twice would double-count).

## Finding game screens: store on construction, look up later

```lua
NotifyOnNewObject("/Script/Dominion.PauseMenuScreen", function(o) pauseSeen[#pauseSeen+1] = o end)
NotifyOnNewObject("/Script/Dominion.Skills2MainScreen", function(o) screens[#screens+1] = o end)   -- cap 20
NotifyOnNewObject("/Script/Dominion.InteractableNPC", function(o) ... end)                        -- queue
```

`usable(w)` accepts only a **live** instance: full name contains `/Engine/Transient` and not `Default__`.
`FindFirstOf` would return the `/Game` archetype instead.

## Skills-screen tile (`skilltile.lua`)

The proof-of-concept notes at the top of the file explain the whole method:

1. Display only; no game skill, save field or data asset is touched.
2. **Clone a real list item:** `StaticConstructObject(itemClass, itemOuter, name, 0, 0, false, false, template = lastItem)`,
   then `TileView:AddItem(clone)`. List items survive closing the screen; **entry widgets are new on every open**.
3. The tile starts off-screen (13th item, 10 shown). Scrolling **reuses entry widgets without any event**, so the tile is
   re-decorated from the tick while the screen is visible: compare each shown entry's `CurrentData` to our item; a reused entry
   showing a real skill gets our label hidden again.
4. Selection: the screen's own `OnSkillTileSelected(item)` updates the right panel (`BP_SetSelectedItem` alone does not).
   When our tile becomes selected without the game's event, call it, then overwrite the texts.
5. Re-decorate at 0, 0.5 and 1.5 s after opening ("lazy icon load").
6. Label at bottom centre so it does not cover the level digit; level formatted as two digits ("07"); panel ring uses the
   radial material's `"Fill Amount"` parameter.
7. Hooks on `Skills2MainScreen` (`OnIntroAnimationFinished` -> open, `OnSkillTileSelected`/`OnSkillTileClicked` -> select,
   `OnEntryWidgetCreated` -> decorate) **only set flags**, ignored while `T.inCall` is true (so our own calls do not re-trigger).
8. If the screen is not built the way the POC saw it, log once and turn the tile off for that world (`T.offWorld`).

## Pause-menu entry and window

- A SLAYER row is added to the pause menu by copying the game's own button-like widgets (`U.buttonLike()` reads from the
  stored `PauseMenuScreen`). Startup-only setting (`ShowInPauseMenu`).
- Controller route: the window **docks inside the pause menu**. Rows are polled with `GetSelected` and linked with explicit
  navigation. B closes the pause menu and the window together. The older floating window stays mouse/keyboard only, never
  opens on a pad, and gives up input once a pad, B/Start, or player movement is seen.
- **Window building:** one window **built once per world**, then only shown, hidden and rewritten. Built from
  `UMG` objects with layout helpers (`U.sized`, `U.pad`, `U.halign`, `U.valign`, `AddChildToVerticalBox/HorizontalBox/Overlay`),
  fixed-height boxes per header line, no `ScrollBox` (clicks in one never reached the click hook) so lists page.
  Reuses the game's button class `WBP_DomAllCapsButton`.
- Window sizes live in a layout table `L` (`W=840, ROW_H=46, ROWS=8, HEAD_H=96...`), tuned from "R-test" findings.

## Items and rewards

`pc.BP_Components_Inventory`: `inv:CanAddItemByData(item, count)` then `inv:AddItemByData(item, count, 100.0, {})`. The author
calls this "Dev Menu's proven route". Checks room first; if there is none the reward is not lost (kept for later).

## Persistence

`%LOCALAPPDATA%\RSDragonwilds\Saved\Slayer-<name>-<id>.json`, one per character; never writes the game save. Purchases write the
point deduction before granting (audit S6: otherwise a crash could repeat a purchase). Reads the character save **offline,
read-only** for `KilledOnceAIs` to know which families have been killed.

## Retire mode

`retire.lua`: if the game ever ships its own Slayer skill, the mod disables itself and keeps data.

## World reset checklist (from `main.lua` ~3696)

On leaving a world: clear window handles (`P.dock`, `P.openPos`), pad state, prompt UI, NPC lists, **drop NPCs queued up
to the last tick spent in the old world** (keep any queued after), drop the stored pause menu, reset retire check, tick
timers and tile state. Reason: a native crash after Exit to Main Menu then re-entering, pressing the key near an NPC.

## Reusable recipes

| Need | Take this |
|---|---|
| Kill detection | `BP_OnDeath` hook + `ThreatSystem.DamageInstigators` credit |
| Talk detection | `Multicast_AcknowledgeInteractionRequest`, owner of arg 1 |
| Get a game screen | `NotifyOnNewObject` store, `/Engine/Transient` filter |
| Add an item to a list UI | clone a real item with `template`, `AddItem`, re-decorate from tick |
| Pause-menu button | copy a game button widget; dock for pads |
| Grant items | `CanAddItemByData` then `AddItemByData(item, n, 100.0, {})` |
| Per-character save | JSON in `%LOCALAPPDATA%\RSDragonwilds\Saved\` |
| Optional self-disable | version/feature detection |

## Cautions

- Tied to dated probes (2026-09-20 to 2026-10-06). The author flags `ScrollBox` clicks, widget rebuilds and
  reused names as crash or dead-click sources.
