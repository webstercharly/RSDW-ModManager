# Guide: building UI (UMG widgets) from Lua

**Use this when** you create your own windows, overlays, panels, cards, icons or text.

## Create widgets

```lua
local cls = StaticFindObject("/Script/UMG." .. name)                 -- CanvasPanel, Overlay, VerticalBox, HorizontalBox, Image, TextBlock, Border, RetainerBox, ScrollBox...
local w   = StaticConstructObject(cls, outerTree [, FName("Unique_"..n)])
```

- **Every object name must be new.** A reused name under the same outer crashed (ResourceAtlas appends a counter: `RA_<name>_<n>`).
- `outer` is the widget tree of the screen it lives in, or the player controller for standalone windows.
- Create a **game user widget** (buttons, panels) with `WidgetBlueprintLibrary:Create(pc, cls, pc)` after `LoadAsset(pkg)` and `StaticFindObject(pkg.."."..asset.."_C")`.

## Layout primitives

| Parent | Add | Then |
|---|---|---|
| CanvasPanel | `slot = parent:AddChildToCanvas(w)` | `slot:SetAutoSize(false); SetPosition({X,Y}); SetSize({X,Y}); SetZOrder(z)`; anchors `SetAnchors({Minimum={X,Y},Maximum={X,Y}})`, `SetOffsets({Left,Top,Right,Bottom})` |
| Overlay | `AddChildToOverlay(w)` | `slot:SetHorizontalAlignment(a); SetVerticalAlignment(a)` |
| VerticalBox / HorizontalBox | `AddChildToVerticalBox(w)` / `AddChildToHorizontalBox(w)` | `slot:SetPadding({Left,Top,Right,Bottom})`, `slot:SetSize({Value=1,SizeRule=1})` to fill |
| Anything | `w:SetVisibility(v)` | 0 visible, 1 collapsed, 2 hidden, 3 HitTestInvisible, 4 SelfHitTestInvisible |

Alignment values: horizontal 0 fill 1 left 2 centre 3 right; vertical 0 fill 1 top 2 centre 3 bottom.

Also seen: `w:SetRenderOpacity`, `SetRenderTransformPivot({X=.5,Y=.5})`, `SetRenderTransformAngle(deg)`, `SetRenderScale`, `SetRenderTranslation`, `RemoveFromParent`, `AddToViewport(z)`, `SetPositionInViewport({X,Y}, false)`, `SetDesiredSizeInViewport({X,Y})`, `ForceLayoutPrepass()` then `GetDesiredSize()` to size to content.

Viewport size: `WidgetLayoutLibrary:GetViewportSize(pc)` divided by `GetViewportScale(pc)`. AurelianUI treats the HUD as 1080 units tall.

## Text

```lua
local tb = new("TextBlock", tree)
local f = tb.Font; f.Size = 16; tb:SetFont(f)
tb:SetColorAndOpacity({ SpecifiedColor = linear, ColorUseRule = 0 })
tb:SetText(FText("..."));  tb:SetJustification(1)
```

- To match the game, build with the game's own text widget `/Game/UI/Common/WBP_DomTextBlock` (`WBP_DomTextBlock_C`) and copy font and colour from a sibling (`w.HealthBar.ValueText.Font`, `.ColorAndOpacity`).
- **Indent with slot padding, not spaces** (a space is a different width at each size).
- Give each header line its own fixed-height box; a 30 pt title and 15 pt subtitle in a 66-unit header spilled over the rule (Slayer).
- Keep strings short: a long second line widens a centred block and drags a neighbouring badge on top of it (EnemyHPNumbers abbreviates `Magical` to `Mag`).

## Images and textures

| Source | How |
|---|---|
| Game texture | `StaticFindObject(path)` else `LoadAsset(path)` then retry; `img:SetBrushFromTexture(tex, false)`; cache by path |
| **Your own PNG, no pak** | `KismetRenderingLibrary:ImportFileAsTexture2D(contextObject, "C:\\...\\file.png")` |
| PNG shipped as bytes | store the bytes in a Lua module, write to disk on first use with `io.open(path,"wb")`, then import (ResourceAtlas, Starfall: hosts reject `.png`) |

- Hold the texture in something live (a widget or a map icon) or the game frees it and the next call re-reads the file. Cache the object and re-validate with `IsValid`.
- Retry a failed load at most every 5 s (AurelianUI `texture()`).
- Tint: `img:SetColorAndOpacity({R,G,B,A})`. Nine-slice borders: `Border` with `Background.DrawAs = 1`, `ImageSize`, `Margin = {Left=.125,...}`.
- sRGB values must be converted to linear first ([reading-writing-values](reading-writing-values.md)).

## Materials

`comp:CreateDynamicMaterialInstance(slot, baseMaterial, FName("None"))` makes a material you can set texture parameters on (SkillPets retextures a game material). Parameter functions exist only on `MaterialInstanceDynamic`; check the class before calling.

## Using the game's own look

- **Panel frame:** `LoadAsset("/Game/UI/Panels/WBP_Panel")`; create it, add children to `frame.PanelContent`, dim the background with `frame.BackgroundPanel:SetRenderOpacity(0.8)`. The frame has a Niagara ember effect (`NiagaraSystemWidget`) that draws a phantom box on custom panels: walk `frame.WidgetTree.RootWidget` (depth limit 10) and `SetVisibility(1)` on it (AutoTool, proven 2026-09-30). The panel's chrome adds 54 units each way.
- **Button:** `/Game/UI/Common/WBP_DomAllCapsButton` (`SetLabelText(FText(...))`; copy `Style`, `TextTransformPolicy`, `bCenterAlignText`, `LeftAlignTextPadding`, `bScrollText` from an existing button such as `pm.SettingsButton`).
- Palettes that match the game: gold `{0.91,0.77,0.48}`, cream `{0.90,0.87,0.80}` (AutoTool); Class Specialisations' gold `{0.5841,0.4020,0.1590}`, ivory `{0.8148,0.8070,0.7835}`, panel `{0.022,0.016,0.011,0.94}`.
- Skills screen art under `/Game/Art/UI/Skills/` (`T_Skill_IconHolder`, `T_Skills_Radial_Centre`, `T_Skills_Diamond`, `T_Skills_Card_Highlight`, `T_Skills_Trim`, `T_Skills_XP_Menu_Bg`...).

## Where to draw

| Target | Method |
|---|---|
| Always-on HUD overlay | find `WBP_HUD_NotificationsOnTop_C` or `WBP_HUD_RootWidget_C` (live instance), add a full-screen `CanvasPanel` at z 880, `SetVisibility(3)` |
| A standalone window | `AddToViewport(700)` with `SetPositionInViewport` (mouse and keyboard only) |
| Inside a game screen | dock into its canvas ([extending-game-ui](extending-game-ui.md)) |

## Lifecycle rules

- **Build once per world, then show, hide and rewrite.** Rebuilding rows on every open crashed UE4SS (Slayer, CollectionLog, QuestLog).
- Pool and reuse: marker widgets, cards, list rows (`SetVisibility(1)` the spare ones). Cap pools (30 lore markers, 6 quest edge markers, 5 pickup cards, 40 pad cells).
- Record a build failure per controller or world and **do not retry** in that world (AutoTool `msgFailedFor`).
- On world change, drop references without calling methods on them.
- Windows should never take clicks unless they are meant to: `SetVisibility(3)` for overlays; `DeactivateWidget()` and `bSupportsActivationFocus = false` for cloned game widgets.
- No `ScrollBox` if you rely on the click hook (clicks inside never reach it); page long lists instead.

## A reusable on-screen message

AutoTool's `showMessage(pc, head, body, seconds)`: one `WBP_Panel` frame with a vertical box and two `WBP_DomTextBlock`s (head 16 pt gold, body 20 pt cream), added at z 700, `SetVisibility(3)`, sized with `ForceLayoutPrepass`/`GetDesiredSize` (+54+12 high, +54+24 wide, clamped 560-1200 by 90-220), centred 330 units above the bottom, hidden by the tick after `seconds`.
RSDWTools' toast does the same job: transient text, re-firing replaces text and resets the timer, no input captured.

## Seen in

[sources/AutoTool.md](../sources/AutoTool.md), [sources/Slayer.md](../sources/Slayer.md), [sources/AurelianUI-Minimap.md](../sources/AurelianUI-Minimap.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/ClassSpecialisations.md](../sources/ClassSpecialisations.md).
