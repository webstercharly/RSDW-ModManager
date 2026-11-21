# MapMarkers 1.0.0: implementation guide

Source: `References/OnlineMods/MapMarkers/1.0.0/extracted/MapMarkers/Scripts/main.lua`
(674 lines, one file). Author: Maxxfilth. No licence stated: learn, do not copy.

**What it does:** lets a player give map pins any of 30 built-in icons and 8 colours, and
optionally raises the 99-pin cap.

**Why read it:** it is a compact, complete example of a UE4SS mod that reads game widgets,
polls input, persists per-character data, integrates Mod Menu and avoids hooks.

## Shape of the file

```text
config table  ->  constants (icons, colours)  ->  helpers (valid, full)  ->  config loader
-> state S  ->  NotifyOnNewObject cap raise  ->  Mod Menu sync  ->  game object finders
-> looks file load/save  ->  map scan  ->  hover/pick  ->  input sampler  ->  save/restore
-> tick()  ->  LoopInGameThreadWithDelay(100) + LoopInGameThreadWithDelay(20)
```

Everything runs in two game-thread loops: a 100 ms `tick` (all logic) and a 20 ms `sample`
(input only). Both are wrapped in `pcall`, with an error counter that logs the first five
failures.

## How each feature works

### 1. Raise the pin cap before the save loads

The game refuses to load a character with more pins than `MaxNumberOfPins`. So:

```lua
NotifyOnNewObject("/Script/Dominion.MapCustomizationComponent", function(o)
    pcall(function() o.MaxNumberOfPins = LOAD_CAP end)   -- 1000
end)
```

- Runs at construction, before the save's pins are applied.
- Does exactly one write and **stores nothing** (storing handles crashed 3 of 3 runs).
- After load, `capTick` (every 2 s) sets the real placing limit with
  `pc:GetMapCustomizationComponent()`. It never goes below the character's existing pin
  count, or the next load would fail.

### 2. Find "the player's markers"

A marker is a `MapIconComponent` whose **owner's class** is `MinimapPluginMapIcons` and whose
`IconTexture` name is one of six vanilla pin textures (`T_Map_Icon_Animal/Base/Ore/Pin/Plant/Tree`,
which map to `PinType` 0-5). No other map icon uses those textures.

```lua
all = FindAllOf("MapIconComponent")           -- once, when the map opens
own = c:GetOwner():GetClass():GetFName():ToString()
tname = c.IconTexture:GetFName():ToString()
x, y = c:K2_GetComponentLocation().X / .Y
```

Per marker it records the original texture and `GetIconDrawColor()` so it can restore them.
Cost measured at about 6 ms for about 110 components.

### 3. Change what a marker looks like

```lua
c:SetIconTexture(tex)        -- tex = StaticFindObject(path), LoadAsset(path) then retry
c:SetIconDrawColor({R=,G=,B=,A=})   -- linear colours
c:SetIconLabel("Cave")       -- text under the marker; cleared after 2.5 s
```

Textures are looked up by **full object path** (for example
`/Game/Art/UI/NavIcons/T_NavIcons_DungeonEntrance.T_NavIcons_DungeonEntrance`) and cached in
a table. If `StaticFindObject` misses, `LoadAsset(path)` then retry. The 30 icon paths in
`ICONS` are a ready list of the game's built-in map and compass icons.

### 4. Know which marker the player means

The author measured that the map's own hover (`MapUIAPI.CurrentlyHoveredMapIcon`) never
reaches player markers. So it computes the pick itself:

1. `view = api:GetMapView()`, `aspect = view:GetViewAspectRatio()`.
2. The view fills the viewport width; height = width / aspect; centred (U=V=0.5 at screen
   centre, measured within 6 px at 1920x1080).
3. For each marker, `view:GetViewCoordinates({X,Y,Z}, false, o, o)` gives U,V in 0..1.
   Screen x = `vw/2 + (U-0.5)*vw`; y = `vh/2 + (V-0.5)*(vw/aspect)`.
4. Mouse key: nearest to `pc:GetMousePosition(o,o)`. Controller button: nearest to screen
   centre (the map's reticle). Pick radius 30 px scaled by `vw/1920`.
5. Out params are passed as plain tables (`local o = {}` then `o.U`, `o.V`).

### 5. Input without hooks or key binds

No `RegisterKeyBind` and no UI hooks. Instead:

```lua
pc:IsInputKeyDown({ KeyName = FName("R") })
```

- UE4SS key names (`PAGE_UP`) become engine names (`PageUp`) by stripping underscores, except
  `Gamepad_*` names.
- A 20 ms sampler, active only while the map is open, detects the **edge** (down now, not
  down before) and appends to a small queue (max 8). The 100 ms tick consumes the queue.
- A 100 ms poll alone missed short taps (1 of 3 in the author's first test).
- Shift reverses direction. Controller uses stick clicks, **not the D-pad**: on the map the
  D-pad opens and closes the quest list.
- `FName` objects are cached per key name.

### 6. Persist per character

- File: `%LOCALAPPDATA%\RSDragonwilds\Saved\MapMarkers-<name>.txt`, tab-separated
  `x  y  icon  color`. Falls back to the mod folder if `LOCALAPPDATA` is missing.
- Character name from `pc.PlayerState:GetPlayerName():ToString()`; `safeName` replaces
  characters outside `[%w-_]` with `_`.
- A stored look belongs to the marker within 30 cm (`MATCH`). A look whose marker is missing
  twice in a row is dropped.
- Writes go to `.tmp` then rename, debounced one second after the last change (`dirtyAt`).
- On character change: flush, reset state, reload.

### 7. Mod Menu integration

- Read: `ModRef:GetSharedVariable("ModMenu.<id>.<key>")`; apply only when `rev` changes; only
  keys in `MM_LIVE` apply live; type must match the config default's type.
- Buttons: Mod Menu sets `ModMenu.<id>.action`; the mod remembers the previous value and acts
  on a change, taking the part before `#` (the rest is a unique suffix).
- Write a status line back:
  `ModRef:SetSharedVariable("ModMenu.request.set", id.."#"..os.time().."-"..n.."|Status="..text)`.

### 8. Save and restore markers (safe removal path)

The mod never removes pins. `MapUIAPI:ClearPin` and `SetHoveredMapIcon` +
`TryRemoveHoveredMapIcon` each **hung the game thread** from Lua (2 of 2, 2026-11-02).
Restore places pins with `api:PlacePin(type, {X=,Y=,Z=})`, skipping any within 30 cm of an
existing one and stopping at the limit.

### 9. World lifecycle

`localPC()` re-validates, checks `IsLocalController()`, excludes names containing `MainMenu` or
`Default__`. When no PC exists the world is gone, so the tick drops every stored handle at once.
`BOOT_GRACE` of 20 s after mod load before any `FindAllOf`.

## API surface it relies on

`MapUIAPI` (`IsShowingMap`, `GetMapView`, `PlacePin`, `CurrentlyHoveredMapIcon`),
`MapViewComponent` (`GetViewAspectRatio`, `GetViewCoordinates`), `MapIconComponent`
(`IconTexture`, `SetIconTexture`, `GetIconDrawColor`, `SetIconDrawColor`, `SetIconLabel`,
`K2_GetComponentLocation`), `MapCustomizationComponent.MaxNumberOfPins`,
`PlayerController` (`IsInputKeyDown`, `IsLocalController`, `GetMousePosition`,
`GetViewportSize`, `GetMapCustomizationComponent`, `PlayerState:GetPlayerName`).

## Reusable recipes extracted

| Need | Take this |
|---|---|
| Edge-detected key polling | Sampler loop plus press queue (section 5) |
| Screen position of a world point on the map | Section 4 maths |
| Per-character sidecar file | Section 6 |
| Mod Menu live settings and buttons | Section 7 |
| Safe world-change cleanup | Section 9 |
| Early write at object construction | Section 1 |

## Things to be careful about

- Not tested here. All measurements are the author's on their build, dated 2026-11-02.
- Over 99 markers makes a character unloadable without the mod. Any feature that raises the
  cap needs that warning.
