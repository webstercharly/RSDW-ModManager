# Guide: keyboard, mouse and controller input

**Use this when** a mod needs a hotkey, a click, a held key, a controller press, or to drive the game's own input.

## Four ways to read a key

| Method | How | Trade-off |
|---|---|---|
| `RegisterKeyBind(Key.F6, cb)` (with optional `{ModifierKey...}`) | callback on the **key thread** | simplest; one author reports crashes under key spam |
| `RegisterKeyBindAsync(Key, mods, cb)` | async variant | used by RSDWTools; no unregister |
| Poll `pc:IsInputKeyDown({KeyName = FName("R")})` on the game thread | your own loop | no key thread at all; edges must be detected |
| `pc:WasInputKeyJustPressed(...)` | per-tick poll | catches discrete pulses such as `MouseScrollUp/Down` |

### Flag-only callbacks

```lua
local REQ = {}
RegisterKeyBind(Key[name:upper()], function() REQ.work = true end)   -- do nothing else here
-- game-thread tick: if REQ.work then REQ.work = false; ... end
```

Used by AutoTool, Slayer (`S.hotkeyReq`, `S.escReq`), SkillPets, ResourceAtlas, AurelianUI (F3).

Official docs: callbacks fire **only when the game or the debug console has focus**; with modifiers use `RegisterKeyBind(Key.O, {ModifierKey.CONTROL, ModifierKey.ALT}, cb)`; `IsKeyBindRegistered(key [, mods])` checks for a clash. **Measured on our build (2026-11-20): the callback runs on a different thread** (`IsInGameThread=false`, `IsInMainModThread=true`) while the game thread keeps running Lua in the same state. Never touch a UObject, a widget or shared tables beyond a plain flag or counter inside it.

### Polling instead (FishingSliders, MapMarkers, EnemyHPNumbers, QuestLog)

FishingSliders `keythread-6` (2026-11-04): a key bind callback runs Lua on UE4SS's key thread while the game-thread loop runs the same Lua state. "Even a callback that only set a flag or added 1 to a counter crashed the game under key spam (4/4), and with every key-bind mod off it survived (0/2)." It replaced all binds with a 33 ms game-thread poll:

```lua
for _, k in ipairs(keys) do
  local d = pc:IsInputKeyDown(k.key)
  if d and not k.down then REQ[k.flag] = true end    -- rising edge
  k.down = d
end
```

A 250 ms main tick is too slow for a quick tap, so use a dedicated 20-33 ms loop. MapMarkers' 20 ms sampler runs **only while the map is open**, queues presses (max 8), and the 100 ms tick consumes them; a 100 ms poll alone missed short taps (1 of 3).

FishingSliders' crash is plausible given the thread result above, but a probe with only a counter in the callback survived 45 presses (up to about 6 per second) with light game-thread Lua, so the crash needs heavier concurrent activity. Prefer polling on the game thread for anything that matters; test key spam on our own hotkeys under real load before relying on a flag-only callback.

### Key names

UE4SS names (`PAGE_UP`, `NUM_ZERO`, `LEFT_MOUSE_BUTTON`) differ from engine names (`PageUp`, `NumPadZero`, `LeftMouseButton`). Convert for `IsInputKeyDown`:
- Letters and `F1`..`F12` pass through.
- Strip underscores, except `Gamepad_*` names (`Gamepad_LeftThumbstick`).
- Digits: `ZERO` -> `Zero`, `NUM_ONE` -> `NumPadOne`.
- Lookup on the UE4SS side: `Key[name:upper()]`; mouse-button aliases (`LeftMouseButton`, `LEFT_MOUSE`...) differ between builds, so try several.
- Cache `FName` objects per key name.

Allow `"none"` to disable a key. A key changed in Mod Menu cannot rebind live (no unregister): log it and show "works after a game restart" (AutoTool).

### Wheel and modifiers

The wheel cannot be hooked (`InputAxis` is native). Poll `WasInputKeyJustPressed(MouseScrollUp/Down)` in a loop that **only runs while a wheel binding exists** (RSDWTools, about 16 ms, "well under 0.1% CPU"); match modifiers with `IsInputKeyDown(LeftShift...)`. Shift can reverse direction in a sampler (MapMarkers).

### Do not hijack keys the game uses

MapMarkers avoided the D-pad because on the map it opens and closes the quest list. QuestLog notes J is taken by the game. Provide `"none"` default for optional keys.

## Mouse position and picking

```lua
local o = {}; pc:GetMousePosition(o, o); x, y = o.LocationX, o.LocationY
local o = {}; pc:GetViewportSize(o, o); w, h = o.SizeX, o.SizeY
```

Scale pixel radii by `vw/1920`. MapMarkers picks the nearest marker to the cursor or, for a pad, to the screen centre (the map's reticle).

## Clicking game buttons

Hook `/Script/CommonUI.CommonButtonBase:HandleButtonClicked`, record `self:get():GetFullName()`, map the name back to your own registry (`ROWS[name] = rowKey`). The hook **only sees mouse clicks**.

## Controller input

A pad's A reaches `HandleButtonClicked` from C++, so the hook never fires. A **selectable** button does get selected. Recipe (QuestLog, CollectionLog, Slayer, Mod Menu, Storage Search all use it):

```lua
b:SetIsSelectable(true)                    -- only after the game has built the button
-- every tick, over your visible buttons:
if b:GetSelected() then
  b:SetIsSelectable(false); b:SetIsSelectable(true)   -- clear it (SetIsSelected(false) is ignored on these)
  routeClick(fullName(b))                              -- same dispatch as the mouse hook
end
```

- For a menu entry that a mouse click also selects, require the selection on two consecutive polls (`PAD.seen`), or let the hook's pick win and just clear the selection.
- **A window added to the viewport never gets pad input.** For pads, dock the window inside the pause menu's canvas ([extending-game-ui](extending-game-ui.md)).
- Set navigation so focus cannot escape: `b:SetNavigationRuleExplicit(dir, target)` with `dir` 0 Left 1 Right 2 Up 3 Down, and `b:SetNavigationRuleBase(dir, rule)`. Link row and column **ends to themselves**. Never link hidden buttons.
- Scroll lists follow focus: `sc:SetScrollWhenFocusChanges(1)`; `sc:ForceVolatile(true)` avoids stale rows.
- Focus: `w:SetUserFocus(pc)`, `w:SetKeyboardFocus()`; refocus the pause entry after closing.
- No text box on pad (a pad cannot type); no scroll boxes where clicks must register (Slayer found clicks inside never reached the hook).
- Large lists on pad: a **fixed pool of at most 40 cells** (`PAGE_MAX`), paged and restyled, never one button per row. "512 game buttons" is the crash profile (CollectionLog).
- A card button where the game's own A takes the press: sample `IsInputKeyDown` at 50 ms on the focused button.

## Input modes with a cursor

To show a window with a cursor while still seeing the menu key and Esc on the game thread (QuestLog):

```lua
pc.bShowMouseCursor = true
wbl:SetInputMode_GameAndUIEx(pc, focusWidget, 0, false, false)       -- fall back to SetInputMode_UIOnlyEx(pc, focusWidget, 0, false)
-- click guard so game clicks do not pass through:
imc = StaticConstructObject(InputMappingContext, gameInstance); ia = StaticConstructObject(InputAction, gameInstance); ia.bConsumeInput = true
imc:MapKey(ia, { KeyName = FName("LeftMouseButton") }) ...
sub = (FindAllOf("EnhancedInputLocalPlayerSubsystem"))[1]            -- once per world
sub:AddMappingContext(imc, priority, {});  -- remove with sub:RemoveMappingContext(imc, {})
```

Check `MapKey`'s parameter names with `fn:ForEachProperty` before use (`Action`, `ToKey`); if it does not match, disable the guard. Release the cursor and remove the context on close.

HUD overlays should never take input: canvas `SetVisibility(3)`, widget `DeactivateWidget()`, `bSupportsActivationFocus = false`.

## Driving the game's own input

FishingSliders' AFK mode injects the game's input actions every frame instead of simulating keys:

```lua
sub:InjectInputVectorForAction(ia, {X=1,Y=0,Z=0}, {}, {})     -- sub = EnhancedInputLocalPlayerSubsystem
-- actions loaded by path: /Game/Gameplay/Inputs/Actions/Basic/IA_PrimaryAction ... IA_Fishing_Reeling
pc:SetControlRotation({Pitch=, Yaw=, Roll=0})                 -- to face a target
```

The game then handles everything as if keys were held. Stop on any invalid object, timeout, or repeated failure.

## Seen in

[sources/MapMarkers.md](../sources/MapMarkers.md), [sources/FishingSliders.md](../sources/FishingSliders.md), [sources/QuestLog.md](../sources/QuestLog.md), [sources/RSDWTools.md](../sources/RSDWTools.md), [sources/AutoTool.md](../sources/AutoTool.md).
