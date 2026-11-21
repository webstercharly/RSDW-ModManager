# ResourceAtlas 1.5 and PenguinFinder 3: map-icon implementation guide

Sources:
- `References/OnlineMods/ResourceAtlas/1.5/extracted/ResourceAtlas/Scripts/` (about 12,400 lines; `nodes/Mining.lua` alone is
  6,700 lines of data), key file `mapicons.lua` (974 lines).
- `References/OnlineMods/PenguinFinder/3/extracted/PenguinFinder/Scripts/main.lua` (1,189 lines).
No licence stated for either: learn, do not copy.

**Why read them:** both put **their own icons on the game's map**. ResourceAtlas documents the performance cost
in detail, which matters for any map markers we add to our minimap (chest markers).

## The most important finding: icons cost frame rate

From the header of `mapicons.lua` (author's measurements, 2026-10-10 to 2026-10-12):

- "The game's map plugin draws any `MapIconComponent`." Each registered component makes a Blueprint widget **with its own
  tick** in the HUD minimap (`WBP_DominionMinimap.AddMapIcon`), the big map, and other mods' minimaps.
- One icon per node (6,000 with badges) took a player from 120+ fps to under 30.
- **A hidden icon costs nearly as much as a shown one.** The minimap's `TickMap` calls every icon widget's `TickIcon` every
  frame, shown or not (read from bytecode, 2026-10-11).
- The game itself has **no HUD minimap**; the big map's own minimap empties itself when it closes. So icons in play only show
  on other mods' always-on minimaps.
- Destroyed icons leave a widget behind in each minimap's list until `ForgetDestroyedIcons` runs, and the game only calls it on
  `SetMapView`.

What it does about it:

1. **Pool, do not create.** At most `MapPoolSize` icon actors, **moved** with `K2_SetActorLocation`, not made, to where needed.
   The pool grows only as far as needed; badges (a second icon) are made only on first show.
2. **Big map open:** icons are grouped per type on a grid, one icon per group with a count. The grid coarsens with zoom and
   further until groups fit the pool. Icons that would overlap are spread round their centre.
3. **Playing:** none unless `MapOnMinimap` is true. Then only the nearest nodes within the radius the minimap shows (read from
   the minimap's view, see below), at most `MapMinimapMax` (default 40).
4. **Shrink:** after the big map has been closed 10 s, icons only it needed are destroyed, then `Purge()` calls
   `m:ForgetDestroyedIcons()` on each minimap and **checks the lists shrank**. If not, it stops destroying icons.
5. Replan only when the player moves `radius/8` (or 2,500 cm); an icon stays until its node is 1.25 radii away (no flicker).
6. Tooltip and label change at most once a minute.

**Lesson for us:** if our minimap draws markers by creating `MapIconComponent`s, keep the count small and pooled. Drawing our own
`Image` widgets (as AurelianUI does with pooled images) avoids that registry entirely.

## Building a map icon

```lua
a = world:SpawnActor(Engine.Actor, origin, rot)                         -- actor has no root; first icon becomes it
icon = a:AddComponentByClass(MapIconComponent class, false, ORIGIN, false)
icon:SetMobility(2)                                                     -- Movable: these move
icon.IconCategory = FName(category)                                     -- no setter in the plugin
icon:SetIconTexture(tex)
icon:SetIconSize(size, 0)                                               -- 0 = screen space
icon:SetIconFogInteraction(3)                                           -- AlwaysRenderAboveFog
icon:SetIconBackgroundInteraction(0)                                    -- every map layer
icon:SetIconInteractable(true)                                          -- hover shows the tooltip
icon:SetIconZOrder(z)
icon:SetIconVisible(false)                                              -- shown later
icon:SetIconTooltipText(FText(tip));  icon:SetIconLabel(label)
```

A **badge** is a second `MapIconComponent` on the same actor with a larger-ring texture and lower z.
**Badge texture without a `.png` file:** CurseForge takes no `.png` in a mod zip, so the picture ships as bytes in `badge_png.lua`, written to disk on
first use with `io.open(..., "wb")` and loaded with `KismetRenderingLibrary:ImportFileAsTexture2D(FindFirstOf("GameInstance"), file)`.
(Note: `require` returns only the module in Lua 5.4 under UE4SS; take one value.)

Icons are on **our** actors because far-away nodes are not loaded by the game.

## Reading the big map's view

```lua
view = screen:BP_GetMapView()  or  screen.Map.MapViewComp        -- screen = WBP_TopNav_Map_C
corners = view:GetWorldCorners()                                  -- TArray; use ForEach(function(_, e) e:get() end)
-- fallback: view:DeprojectViewToWorld(u, v, out) for UV (0,0) and (1,1)
box = min/max of corner X,Y        -- accept only if bigger than 100 uu each way
```

## Finding other mods' minimaps and their reach

```lua
FindAllOf("WBP_DominionMinimap_C")      -- skip Default__ and the TopNav one (the big map's)
m.Icons:GetArrayNum()                   -- >0 means an always-on minimap holds icons
m.MapViewComp -> corners -> radius from centre; if m.bIsCircular then radius / sqrt(2)
```

Re-checks only when none is known, at most every 30 s. Radius is accepted between 2,000 and 500,000 cm.

## Other architecture

- **Parts in pcalls:** `overlay`, `panel`, `legend`, `mapicons`, `maplegend`, `farm` are `require`d through `LoadPart` (pcall); a part failing
  3 times in a row turns off. Config via `config.lua`; filters, state and node categories in separate modules.
- **Node categories** (`nodes/Mining, Trees, Essence, Anima, Farming, Fishing`) are data tables of node positions, the game's rune
  and ore map coordinates, drawn from data not scans, because far nodes are not loaded.
- **Map position transform:** `C.MapPos(x, y, z)` shifts Scorned Wilderness coordinates onto its painted position.
- **Squared distances as floats:** "squared integers overflow 32-bit Lua" in the author's offline test harness. Multiply by 1.0.
- Keys: `RegisterKeyBind`, F4 legend, F6 tracker; respawn countdowns read from `ResourceRespawnComponent` and `InGameTimeActor`.

## PenguinFinder 3: pin overrides and a custom pin picture

**What it does:** shows collectable penguin locations as map pins, and lets co-op players see their own set.

Key mechanism: it **replaces the pin list a client receives**.

```lua
RegisterHook("/Script/Dominion.MapCustomizationComponent:Client_NotifyPinsSet", pre, post)
comp:Client_NotifyPinsSet({ { Handle = h, PinType = t, Location = { X = x, Y = y } }, ... })   -- call it yourself, guarded by `applying`
```

- Mod pins use a handle base of **65000** (`PIN_HANDLE_BASE`) so they never clash with player handles; `PinType 0`. The cap is
  99, so the sent list is "player's own pins first, then the nearest penguins that fit the remaining room".
- A re-entrancy flag `applying` is set around its own `Client_NotifyPinsSet` call so the hook ignores the call it made itself.
- When the game sends a list that contains **no** mod pins, it remembers the player's own pins and asks for a resend; if the
  game's list is missing pins it had, it sends the merge back 100 ms later.
- Also hooks `Server_NotifyPinPlaced`, `Server_NotifyPinCleared`, `LocalPlayerAudioSubsystem:HandleMapPinAdded/Removed` to keep a
  shadow copy of other players' pins (persisted to `remote_pins.txt`).
- **Retexture:** after pins are drawn, `retexture()` finds the pin icons (`FindAllOf("MapIconComponent")`) for handles at or above
  the base and sets a custom texture; re-run 100 ms later and whenever the map opens (`WBP_TopNav_Map_C:BP_OnMapMaximised` sets
  a flag after 250 ms). The picture is `penguin_icon.png`, loaded with `ImportFileAsTexture2D`; fallback
  `/Game/Art/UI/NavIcons/T_Map_Icon_Animal`.
- Pin moves are ignored under 500 units (`MOVE_TOL2`) so the list is not resent for tiny changes; a "join resend" repeats after
  15 ticks so a new player gets the pins.
- Hooks are installed through `tryHooks()` on the tick, each marked in `hooksDone`, retried until all succeed. Hook bodies are
  wrapped in `pcall` after copying args into a table (`{...}` then `table.unpack`).
- `later(ms, fn)` is the mod's own delayed-call helper driven by the tick.

## Reusable recipes

| Need | Take this |
|---|---|
| Many markers cheaply | pooled `MapIconComponent` actors, move not create, shrink + `ForgetDestroyedIcons` |
| Our own pin picture | PNG via `ImportFileAsTexture2D`, or bytes in a Lua module written to disk first |
| Group markers by zoom | grid cells sized from the map view's world box |
| Override what the game shows as pins | hook `Client_NotifyPinsSet`, merge, resend with a re-entrancy flag |
| Read any minimap's range | `MapViewComp:GetWorldCorners()` |
| Fail one feature, keep the rest | per-part `pcall` + 3-strike disable |

## Cautions

- Performance numbers are from a specific build and player counts; re-measure if we add icons.
- PenguinFinder's pin handles above 65000 depend on the game accepting arbitrary handles; it has been tested only by its author.
