# AurelianUI 2.0, minimap and HUD overlay: implementation guide

Source: `References/OnlineMods/AurelianUI-HUD-Overhaul/2.0/extracted/ue4ss/Mods/AurelianUI - HUD Overhaul/`
`Scripts/main.lua` (about 4,500 lines, shared helpers, HUD restyle) and `Scripts/minimap.lua`
(2,757 lines, minimap, pickup cards, ammo counters, notification moves). Credits Relic Hunter UI for
HUD widget names. No licence stated: learn, do not copy.

**Why read it:** it is the only reference here that builds an in-game minimap, which is the same job
as the Map module's `rlm_minimap.lua`. Our own minimap work reaches many of the same conclusions.

## Architecture

`minimap.lua` returns `function(C)`. `C` is a context table from `main.lua` holding helpers
(`log, get, valid, full, fname, cname, kids, texture, new_widget, load_obj, live_root, style_text, S,
mod_dir`). All state sits in one table `M` (`M.mm` minimap, `M.pk` pickups). A staged state machine
drives it, so nothing depends on timing luck:

```text
wait  -> let world settle 4 s, find the map widget class (else wait for the player to open M once)
init  -> 0.5 s after build: check_started()
detect-> work out which MapViewComponent rotation mode turns the map (tests 3 modes x 2 angles)
run   -> follow() every tick; slow jobs on 1 s / 2 s timers
off   -> a step that cannot work turns only the minimap off
```

Every step writes a line to `AurelianUI_minimap_report.txt` (the previous launch's file is kept), so a
native crash leaves the last completed step in a file.

## Shared helpers (main.lua)

| Helper | What it does |
|---|---|
| `get(fn, default)` | `pcall(fn)`, value or default |
| `valid(o)` | `IsValid` in pcall |
| `live_root(cls)` | `FindAllOf(cls)`, return the instance whose full name contains `/Engine/Transient` (the live one, not a class default or editor copy) |
| `new_widget(name, outer)` | `StaticConstructObject(StaticFindObject("/Script/UMG."..name), outer)` |
| `texture(name)` | read PNG from `art/` with `KismetRenderingLibrary:ImportFileAsTexture2D(pc, path)`, cached; retry at most every 5 s |
| `load_obj(path)` | `LoadAsset` then `StaticFindObject` |
| `kids(w)` / `each_desc(w, fn, depth, max)` | `GetChildrenCount` / `GetChildAt` walks, depth limited |

**`ImportFileAsTexture2D` is how a mod ships its own PNG art without a pak.** Texture objects are
cached in a table and re-validated with `IsValid` before reuse.

## Where it draws: an overlay canvas

`overlay()`:
1. `root = live_root("WBP_HUD_NotificationsOnTop_C") or live_root("WBP_HUD_RootWidget_C")`.
2. `tree = root.WidgetTree`, `top = tree.RootWidget`; if `top` is not an `Overlay` or `CanvasPanel`,
   search up to depth 3 for one.
3. Create a new `CanvasPanel`, add to host (`AddChildToOverlay` + alignment, or `AddChildToCanvas` +
   anchors 0..1, offsets 0, `SetZOrder(880)`).
4. `canvas:SetVisibility(3)` (HitTestInvisible) so the overlay never takes the mouse.

`put(parent, w, x, y, wd, ht, z)` is the layout primitive: `AddChildToCanvas`, `SetAutoSize(false)`,
`SetPosition`, `SetSize`, `SetZOrder`. All further drawing hangs off that canvas.

## Building the minimap (`build`)

1. **Get the game's map widget class.** `FindAllOf("WBP_DominionMinimap_C")` then `w:GetClass()`.
   The M map creates one, so the player must open the map once per install. The class path is saved to
   `AurelianUI_minimap_class.txt` and re-loaded with `load_obj` on later launches, which removes that need.
2. **Create its own map view.** `StaticFindObject("/Script/MinimapPlugin.MapViewComponent")`, then
   `pawn:AddComponentByClass(vc, false, transform, false)`, `comp:SetAbsolute(false, true, false)`.
   Copy collision profile (`GetCollisionProfileName`/`SetCollisionProfileName`), box extent
   (`GetUnscaledBoxExtent`/`SetBoxExtent`) and `GetCollisionEnabled`/`SetCollisionEnabled` from the
   character's own `pawn.MapView` "so the game treats it exactly like that one". Then
   `comp:SetViewExtent(MM_RANGE, MM_RANGE)` (15000 = how much world the disc shows).
3. **Create the widget** `WidgetBlueprintLibrary:Create(pc, cls, pc)` and set properties before it is shown:
   `bIsCircular=true`, `bEnableBoxSelect=false`, `bDrawCamera=false`, `bAutoActivate=false`,
   `bSupportsActivationFocus=false`, `IconScale`, `AutoLocateMapView=0`, `MapViewComp=<our view>`,
   `FillColor` transparent.
4. **Layer stack inside a holder canvas** (z-order in brackets): dark disc image (0), `mapbox`
   canvas holding the map widget (1), lore/marker canvas (2), ring PNG (3), edge-marker canvas (5), north
   marker image (4). Holder opacity starts at 0 and goes to 1 only once the stage reaches `run`.
5. **Round mask of its own.** Put the map widget inside a `RetainerBox`. Later copy the game's own circle
   material from `w.RetainerBox_Minimap:GetEffectMaterial()` (use `mid.Parent` when it is a dynamic instance)
   with `rb:SetEffectMaterial(mat)` and `SetTextureParameter`, then switch the map's own mask off with
   `grb:SetRetainRendering(false)`. Reason: the white square corners.

## Starting the widget (`check_started`)

0.5 s after create: verify `w.MapViewComp` is ours, else `w:SetMapView(MM.view)`; force `bIsCircular`;
`w:ReinitShape()`, `w:InitFillBackground()`; fix edges, clip, fog; if `w:IsActivated()` then
`w:DeactivateWidget()`. Reads `Switcher_MapActive:GetActiveWidgetIndex()` and `w.Icons:GetArrayNum()` for the
log.

## Rotation (`detect_step` and `follow`)

- `MapViewComponent.RotationMode` has several values. At startup the mod tests modes 0,1,2 at two angles and
  keeps the one whose projected movement differs by about 90 degrees (a "turning" mode).
- Per tick: `view:K2_SetWorldRotation({Pitch=0, Yaw=yaw+offset, Roll=0}, false, {}, true)` with `yaw` from
  `pc:GetControlRotation().Yaw`.
- Calibration: project a point 1000 uu forward with `GetViewCoordinates`, measure its on-screen angle, derive
  `yaw_off` so forward is straight up, re-nudge every second if drift exceeds 3 degrees.
- Fallback if the view cannot turn: `mapbox:SetRenderTransformAngle(deg)` rotates the picture and every
  marker position is rotated by the same angle.

## Coordinates

`uv(view, p)` wraps `view:GetViewCoordinates({X,Y,Z}, true, tu, tv)` and reads `U`,`V` (0..1) from either
out table (the return can come back in the tables or in extra return values, so it checks both).
`to_screen(u,v)`: `dx=(u-0.5)*D*0.92`, then rotate by the hand-turn angle, add centre.
`screen_angle(view,p,dx,dy)`: project two points, `atan2` of the UV difference.

## Marker types drawn on top

- **North marker:** angle of world +north vector (`MM.northv`) projected, placed at radius `R-2`.
- **Lore markers:** per-world list, up to 30, shown only inside radius `R - size`, pooled widgets reused;
  unused ones set `SetVisibility(1)` (collapsed).
- **Off-range quest markers:** from `e.comp:K2_GetComponentLocation()` relative to player: world distance vs
  `vis_r` (the minimap's edge in world units, measured from the view: `0.5 * 1000 / |uv step|`). Hysteresis:
  out when `wd > vis_r * 1.03`, back in when `wd < vis_r * 0.95`. Placed on the ring at `R * RING_MID` with a
  dark disc behind. Pooled.

## Fog and explored regions

Documented in [guides/map-and-minimap.md](../guides/map-and-minimap.md). The key point here is how it ends up:
the fog layer is **left exactly as the game draws it** and the game's explored-regions record is **copied**
from the M map into the minimap, saved per world to `AurelianUI_minimap_regions_<world>.txt`, and
re-applied on load, when fog layers change, and every 5 s.

## Stability timers

- Round masks: `SetRenderingPhase(0,1)` once then `RequestRender()` every 0.5 s.
- Own mask rebuilt (`SetRetainRendering(false/true)`, re-clip, `RequestRender`) at 1, 4, 10, 20, 40 s after
  start and on any screen-size change: "the mask's picture of the map is bound when it is first drawn".
- Quest markers: if the minimap has none at 3 s and 8 s after start, it calls
  `FindFirstOf("BP_Components_QuestProgress_C"):OnRep_VisibilityTrackers({})`. Only the marker message; a full
  tracker refresh made the tracker blink.
- Per-world and per-character reset: if `MM.pawn ~= full(pawn)`, remove holder from parent (`RemoveFromParent`)
  and restart the stage machine, keeping the cached class.
- HUD rebuilt by the game: if holder is no longer valid, go back to `wait`.

## Other overlay features (same canvas)

- **Pickup cards**: hide the game's pickup list, read each item's name, amount and icon from the game popup,
  draw a card (gold frame, item icon, text), queue with a 0.35 s stagger, max 5, 4 s each.
- **Ammo and spell counters**: copy the count and icon widgets into the hotbar slot that holds the active
  weapon; find slot rectangles from the HUD, with a derived fallback.
- **Notification moves** (`Level Up`, `Region Discovered`, XP gains): shift existing game widgets by
  fixed amounts using render translation, never by measuring.
- **Compass hide**: keep it at opacity 0.004 so it keeps running.

## Reusable recipes

| Need | Take this |
|---|---|
| Find the live HUD to draw on | `live_root` with `/Engine/Transient` filter |
| Overlay that never steals input | Canvas at z 880, `SetVisibility(3)` |
| Ship PNG art without a pak | `ImportFileAsTexture2D` plus a cache |
| Reuse a game widget class we never loaded | save its path to a file once the player has opened it |
| Dependency-free state machine | stages `wait/init/detect/run/off`, retry timers |
| Per-step report file | write each step, keep previous launch's file |
| Pooled marker widgets | create on demand, `SetVisibility(1)` the spare ones |
| Off-range indicator | measure the view's edge from the view itself, add hysteresis |

## Differences from what we do

Compare with the Map module's `rlm_minimap.lua`: we clone `WBP_DominionMinimap_C` in the HUD as well. Items AUI does
that our HANDOFF does not mention: own `MapViewComponent` on the pawn, a separate `RetainerBox` mask with the
game's circle material, mask refresh schedule, copy of explored regions rather than forcing
`FogRevealedRegions`, and rotation-mode detection. Worth testing each if our disc still shows corners, or
fog problems.
