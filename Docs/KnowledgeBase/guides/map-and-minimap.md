# Guide: the map, map pins, map icons and building a minimap

**Use this when** you read or change pins, add your own map icons, convert world positions to map or screen positions, or build a minimap.

## Objects involved

| Object | Role |
|---|---|
| `WBP_TopNav_Map_C` | the big map screen; hooks `BP_OnMapMaximised` / `BP_OnMapMinimised`; `screen.Map.MapViewComp`, `BP_GetMapView()` |
| `MapUIAPI` (`FindFirstOf`) | `IsShowingMap()`, `GetMapView()`, `PlacePin(type, {X,Y,Z})`, `PlaceWaypoint`, `ClearWaypoint`, `CurrentlyHoveredMapIcon` |
| `MapCustomizationComponent` (`pc:GetMapCustomizationComponent()`) | pins; `MaxNumberOfPins`, `CurrentWaypoint`; RPCs `Client_NotifyPinsSet`, `Server_NotifyPinPlaced/Cleared` |
| `MapIconComponent` (`/Script/MinimapPlugin.MapIconComponent`) | one drawn icon; lives on an actor (player pins on `MinimapPluginMapIcons`) |
| `MapViewComponent` (`/Script/MinimapPlugin.MapViewComponent`) | a camera over the map: extent, rotation, coordinate conversion |
| `WBP_DominionMinimap_C` | the map widget (also behind the HUD minimap): `MapViewComp`, `Icons`, `bIsCircular`, `RetainerBox_Minimap`, `Canvas_Backgrounds`, `Switcher_MapActive` |

## Pins (player markers)

- Stored in the character save: `GameProgress.MapCustomization.Pins` = `PinType` 0-5 plus x, y. Types match six textures: `T_Map_Icon_Animal, Base, Ore, Pin, Plant, Tree`.
- A drawn player pin = `MapIconComponent` whose owner class is `MinimapPluginMapIcons` and whose `IconTexture` is one of those six.
- Find them: `FindAllOf("MapIconComponent")` **once when the map opens** (about 6 ms for 110), filter by owner and texture, read `K2_GetComponentLocation()`.
- Restyle: `c:SetIconTexture(tex)`, `c:SetIconDrawColor({R,G,B,A})`, `c:SetIconLabel(text)` (clear later). Keep each marker's original texture and colour so you can restore it. Match stored looks to markers by position within 30 cm; drop a look whose marker is missing twice.
- **The game cap is 99** and a character with more **fails to load** ("LoadPinsFromJson: Too many pins"). To raise it, set `MaxNumberOfPins` in `NotifyOnNewObject("/Script/Dominion.MapCustomizationComponent", ...)` before the save applies (one write, store nothing), then set the real limit after load and never below the existing count. Warn users that removing the mod with more than 99 pins breaks that character. The mod must never remove pins itself (`ClearPin` hung the thread).
- Place a pin: `api:PlacePin(type, {X=,Y=,Z=})` (works; skip any within 30 cm of an existing one).
- Waypoint: `api:PlaceWaypoint({X,Y,Z})` is **asynchronous** (round-trips through `Server_NotifyWaypointPlaced`); poll `mcc.CurrentWaypoint`, never confirm from the return. Using it gives the compass marker, distance and styling for free.
- Native waypoint input can bypass the `MapUIAPI:PlaceWaypoint` Lua hook (observed 2026-11-21: a registered hook saw no calls when a player placed a waypoint). When handling the server notification, match the receiving component to the local controller's component before acting. Hosts also receive notifications for guests.
- **Override what the client receives** (PenguinFinder): hook `Client_NotifyPinsSet`, merge your extra pins (handles above 65000, `PinType 0`) with the player's own, and call `comp:Client_NotifyPinsSet(list)` yourself behind an `applying` flag. Pin structure: `{Handle=, PinType=, Location={X=,Y=}}`. Max 99 in the list.
- The map's own hover never reaches player pins (measured). To pick one yourself see "Screen position" below.

## Adding your own icon

Two ways.

**A. Icon on a spawned actor (Starfall, ResourceAtlas):**

```lua
actor = world:SpawnActor(TargetPoint or Actor class, pos, rot)               -- exists on this machine only
icon  = actor:AddComponentByClass(MapIconComponent class, false, NO_OFFSET, false)
icon:SetMobility(2)                                                            -- if you will move it
icon:SetIconTexture(tex); icon:SetIconSize(50, 0)                              -- 0 = screen space units
icon:SetIconFogInteraction(3)                                                  -- AlwaysRenderAboveFog
icon:SetIconBackgroundInteraction(0)                                           -- every map layer
icon:SetIconInteractable(true)                                                 -- hover tooltip
icon:SetIconZOrder(z); icon:SetIconTooltipText(FText(name)); icon:SetIconVisible(true)
icon.IconCategory = FName("MyCat")                                             -- no setter
```

A second `MapIconComponent` on the same actor is a "badge" (ring behind the icon).

**B. Draw your own widgets** on the minimap you build (AurelianUI): no `MapIconComponent`, no registry cost.

### The icon performance trap (ResourceAtlas, measured 2026-10-10 to 10-12)

- Each registered `MapIconComponent` makes a Blueprint widget **with its own tick** in every minimap (the HUD one, the big map, other mods').
- 6,000 icons took a player from 120+ fps to under 30.
- **A hidden icon costs almost as much as a shown one** (`TickMap` calls every icon's `TickIcon` every frame).
- **Pool them:** at most N icon actors, moved with `K2_SetActorLocation`, not created. Grow only as needed; make badges only on first show.
- Group by grid cell when zoomed out (one icon per group with a count); limit play-time icons to what a minimap shows (read its view reach); replan only after the player moves `radius/8`; keep an icon until its node is 1.25 radii away (no flicker); change tooltips at most once a minute.
- Destroying icons leaves widgets behind in each minimap's list until `ForgetDestroyedIcons()`; the game only calls it on `SetMapView`. After destroying, call `m:ForgetDestroyedIcons()` on each minimap and **check the lists shrank**; if not, stop destroying.

## Screen position and view coordinates

```lua
view = api:GetMapView()                                    -- or minimapWidget.MapViewComp
view:GetViewAspectRatio()
view:GetViewCoordinates({X=wx, Y=wy, Z=0}, false, tU, tV)  -- U and V in 0..1 across the view (read from either table)
view:GetViewExtent(outX, outY);  view:SetViewExtent(x, y)  -- world units across the view
view:GetWorldCorners()                                      -- TArray of corners (use ForEach); fallback DeprojectViewToWorld(u, v, out)
```

Big map on screen: the view fills the viewport width; height = width / aspect; centred (U=V=0.5 at screen centre, accurate to 6 px at 1920x1080):
`sx = vw/2 + (U-0.5)*vw`, `sy = vh/2 + (V-0.5)*(vw/aspect)`.
Pick a marker: nearest to `pc:GetMousePosition` (radius 30 px scaled by `vw/1920`), or nearest to screen centre for a pad.

World-direction on screen: project two points and take `atan2(dV, dU)` (AurelianUI `screen_angle`).

## Building a minimap from the game's map widget (AurelianUI 1.5.x)

1. **Class:** `FindAllOf("WBP_DominionMinimap_C")` then `w:GetClass()`; the big map makes one, so the player must open the map once. **Save the class path to a file** and `LoadAsset` it on later launches.
2. **Your own view:** `pawn:AddComponentByClass(MapViewComponent class, false, transform, false)`, `comp:SetAbsolute(false, true, false)`; copy collision profile, box extent and collision from `pawn.MapView`; `comp:SetViewExtent(range, range)` (15000 shows about a 150 m disc; 15,000/30,000/60,000 for 50/100/200 m is our own calibration).
3. **Create the widget** with `WidgetBlueprintLibrary:Create(pc, cls, pc)` and set before showing: `bIsCircular = true`, `bEnableBoxSelect = false`, `bDrawCamera = false`, `bAutoActivate = false`, `bSupportsActivationFocus = false`, `IconScale`, `AutoLocateMapView = 0`, `MapViewComp = yourView`, `FillColor` transparent.
4. **Stack** (z): dark disc 0, map canvas holding the widget 1, markers 2, ring PNG 3, north marker 4, edge markers 5. Holder opacity 0 until ready.
5. **After about 0.5 s:** confirm `w.MapViewComp` is yours (else `w:SetMapView(view)`), `w:ReinitShape()`, `w:InitFillBackground()` only if `Canvas_Backgrounds:GetChildrenCount() == 0`, `w:DeactivateWidget()` if `IsActivated()`.
6. **Round mask of your own:** put the widget inside a `RetainerBox`; copy the game's circle material from `w.RetainerBox_Minimap:GetEffectMaterial()` (`mid.Parent` for a dynamic instance) with `rb:SetEffectMaterial(mat)` and `SetTextureParameter`; switch the map's own mask off with `grb:SetRetainRendering(false)`.
7. **Keep the mask alive:** `SetRenderingPhase(0,1)` once, `RequestRender()` every 0.5 s; rebuild the mask (`SetRetainRendering(false)` then `true`, re-clip, `RequestRender`) at 1, 4, 10, 20, 40 s after start and on screen-size change ("the mask's picture is bound when first drawn; before the map is ready it can keep a blank white picture all session").
8. **Rotation:** test `MapViewComponent.RotationMode` values 0-2 at two angles and keep the one that turns the view; each tick `view:K2_SetWorldRotation({Pitch=0, Yaw=yaw+offset, Roll=0}, false, {}, true)` with `yaw = pc:GetControlRotation().Yaw`; calibrate `offset` by projecting a point 1000 uu forward so forward is up, re-nudge every second if drift exceeds 3 degrees. Fallback: `mapbox:SetRenderTransformAngle(deg)` and rotate your marker positions by the same angle.
9. **Fog and backgrounds** (the common failure):
   - `FogRevealedRegions = (0,0,0,0)` makes the shader paint black. `SetFogRevealedRegions({R=1,G=1,B=1,A=1})` reveals everything (our own finding).
   - AurelianUI instead left the fog layer exactly as drawn (changing it brought back the white square corners) and **copied the game's explored-regions record** from the big map, saved per world (`..._regions_<world>.txt`), re-applied on load, when fog layers change, and every 5 s.
   - Backgrounds are attached by the Blueprint constructor; calling `InitFillBackground()` twice duplicates them (six stacked widgets in our logs).
   - A dungeon texture (`T_Map_Dowdun_Underground`) drawn last covers the surface landmass (`T_WorldMap_Landmass`): filter background children by what the player is standing on.
   - Material parameter reads only on dynamic instances; query only the named images (`ImageBackground`, `Image_OpaqueBackground`), never every image (the shadow frame crashes).
10. **Quest markers:** the game fills them when told its trackers changed; if the minimap has none at 3 s and 8 s after start, call `FindFirstOf("BP_Components_QuestProgress_C"):OnRep_VisibilityTrackers({})` (marker message only; a full refresh makes the tracker blink). Off-range markers: measure the minimap edge from the view (`0.5*1000/|uv step|`), place on the ring with hysteresis (out at 1.03x, back at 0.95x).
11. **Own markers:** pooled `Image` widgets on a canvas above the map; positions from `GetViewCoordinates` then rotate with the hand angle; show only inside radius minus size.
12. **Never act as a menu:** canvas `SetVisibility(3)`, widget deactivated.

Stage machine and per-step report file: [execution-model](execution-model.md).

## Pitfalls

- `FindAllOf("MapIconComponent")` per frame (stall).
- Creating icons per node (frame rate).
- Raising the pin cap without the removal warning.
- Reading soft references on map icons or textures ([reading-writing-values](reading-writing-values.md)).
- Forcing fog on the HUD clone when it shares a layer with the big map (open question for us).

## Seen in

[sources/AurelianUI-Minimap.md](../sources/AurelianUI-Minimap.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/MapMarkers.md](../sources/MapMarkers.md), [sources/Starfall.md](../sources/Starfall.md), [sources/QuestLog.md](../sources/QuestLog.md).
