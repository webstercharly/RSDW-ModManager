# Guide: changing and extending the game's own UI

**Use this when** you add to or restyle screens the game already has: the pause menu, HUD bars, skills screen, inventory, popups, notifications.

## Principles that held across every mod

1. **Reuse a game widget instead of making one** when the layout, scaling, facing and visibility rules should be inherited (EnemyHPNumbers writes into an unused `DebugHealthValues` TextBlock).
2. **Do not destroy the game's original widget.** Move it off-screen or make it invisible so its logic keeps feeding values (AurelianUI keeps the original bars alive off-screen; its compass is kept at opacity 0.004 "invisible but still running" because it updates quest markers).
3. **Capture the original state before the first write and restore it** when you stop (text, visibility, parent). Game widgets are pooled; a stale value rides to the next owner.
4. **Find widgets by class name or by picture, never by position or measurement.** Measuring geometry crashed AurelianUI (v8); later versions use fixed translations.
5. **Move the specific element, not its container** (a container held the quest list too).
6. **Search every root.** The game has two HUD roots (`WBP_HUD_RootWidget_C`, `WBP_HUD_NotificationsOnTop_C`).
7. A deactivated widget can still draw: do not rely on "is it in the viewport" (AurelianUI hotbar).

## Add a button to the pause menu

(From QuestLog, "the same block in every mod".)

1. Store the menu when the game builds it:
   `NotifyOnNewObject("/Script/Dominion.PauseMenuScreen", function(o) seen[#seen+1] = o end)`; fallback one `FindFirstOf("WBP_PauseMenuScreen_C")` shortly after Esc. Take the newest; reject `Default__`.
2. Make a game-styled button: `LoadAsset("/Game/UI/Common/WBP_DomAllCapsButton")`, `WidgetBlueprintLibrary:Create(pc, cls, pc)`, copy style fields from `pm.SettingsButton`, `b:SetLabelText(FText("MY MOD"))`.
3. Insert into `pm.VerticalBox_PauseMenu` **between SETTINGS and the exits**. The game's own entries are `ResumeButton`, `AgilityCourseSection`, `PlayerListButton`, `WorldDetails`, `SettingsButton`, `ExitToMainMenuButton`, `ExitToDesktopMenu`. Remove the extras and exits with `box:RemoveChild`, **sort all mod entries by label** (strip a leading `SHOW `/`HIDE `), re-add them, then the exits. Every mod re-sorts, so entries from several mods coexist in a stable order.
4. Re-check every few ticks (the menu is rebuilt); verify the box still contains your button, else mark `broken` and fall back to a key.
5. Click: hook `CommonButtonBase:HandleButtonClicked`, record the name. Open: call `pm:Resume()` to close the menu, then open your window one tick later.
6. Pad: make the button selectable and poll `GetSelected()` ([input](input.md)).
7. `fitPauseList(box)` grows the list so the D-pad reaches every entry.

## Dock a window into a game screen

```lua
root = pm.WidgetTree.RootWidget                         -- pause menu: BackgroundBlur wrapping a CanvasPanel
canvas = (root's class == "CanvasPanel") and root or root:GetContent()
slot = canvas:AddChildToCanvas(frame)
slot:SetPosition({X=600,Y=170}); slot:SetSize({X=W,Y=H}); slot:SetZOrder(100)
frame:SetRenderTransformPivot({X=0,Y=0}); frame:SetRenderScale({X=0.9,Y=0.9})
```

- Only when `pm:IsActivated()`. Build once per menu instance, then only show and hide.
- This is what makes **controller input** work: a viewport window never gets pad input.
- **One docked panel at a time across mods:** shared variables `PauseDock.owner` and `PauseDock.rev`. Claim = bump `rev`, set `owner`. If `rev` moved and `owner` is someone else, close yourself. Do not close on a failed read.
- Docking into the inventory: the root canvas is `WBP_Inventory_MainPanel_C` (reject template copies with `:WidgetTree.`). It never hides, so follow `BackgroundPanel.BackgroundPanel` visibility (0 open, 1 closed) and step aside while a processing-station window is open.

## Restyle or relocate HUD elements

| Technique | Detail |
|---|---|
| Hide | `SetVisibility(1)` (collapsed), or opacity 0.004 to keep it running |
| Move | fixed `SetRenderTranslation` or slot offsets, not measured positions; scale about the element's own corner (`SetRenderTransformPivot({X=0,Y=0})`) |
| Find | by class (`WBP_HUD_QuestList_C`, `WBP_HUD_HeldEquipmentEffectListEntry_C`, `WBP_TutorialNotifications_Item_C`, `PlayerVitalsWidget`) or texture name; `FindAllOf` then keep `/Engine/Transient` |
| Replace a popup | hide the game's, read its data (name, amount, icon), draw your own card; hide its particle effects too (`NiagaraSystemWidget`) or they linger |
| Position from the game | follow the real hotbar slot rectangles; if the game does not report them derive from where the HUD puts the hotbar |
| Badges | put them **inside** the slot so the slot centres them |
| Notification queues | lift the game's own queue (`AchievementLevelUpSkillUnlock`) by a fixed amount rather than rebuilding it; the game shows one at a time |
| Text that must not appear | check the popup while still invisible and re-announce only once its data exists ("[Missing Data] No 'Subobjective Text' set") |
| A message that arrives before its widget | record and replay once the widget exists (the tracked-quest load message) |
| Bar fill | `widget.VitalFillValue` is the drawn 0-1 fraction; `VitalBarValue` is not |

HUD overlays should be click-through: canvas `SetVisibility(3)`; cloned game widgets `DeactivateWidget()` and `bSupportsActivationFocus = false`.

## Add a tile to a game list (Skills screen)

(Slayer, display-only.)
1. Clone a real list item: `StaticConstructObject(itemClass, itemOuter, name, 0, 0, false, false, template = lastItem)`, then `TileView:AddItem(clone)`. List items survive closing the screen; **entry widgets are recreated on every open**.
2. The tile starts off-screen. Scrolling **reuses entry widgets without any event**, so re-decorate from the tick while the screen is visible: compare each shown entry's `CurrentData` to your item and hide your label where a reused entry now shows a real skill.
3. Selection: call the screen's own `OnSkillTileSelected(item)` when your tile becomes selected without the game's event, then overwrite the text.
4. Re-decorate 0, 0.5 and 1.5 s after opening (lazy icon load).
5. Hooks on the screen only set flags and are ignored while your own call is running.
6. If the screen is not built the way you expect, log once and turn the feature off for that world.
7. An item with an empty data struct can crash the game's own tile code, so clone a real one.

## Add text to a game bar

(EnemyHPNumbers.) Option A: write to an existing unused TextBlock (enemy bars: `DebugHealthValues`; set text and `SetVisibility(4)`). Option B: construct a `TextBlock`, `AddChildToOverlay` on the bar's overlay (`bar.WidgetTree.RootWidget:GetChildAt(1)` must be an `Overlay`; log and skip if not), centre it, copy font and colour from a sibling, and `RemoveFromParent` on reset. Boss bars and player bars need option B.

## Show text and messages through the game's own systems

| Need | Call |
|---|---|
| A top-of-screen band for all players | `controller:Client_DisplayTextNotification({TagName = FName("UI.Notification.Event.Velgar.AttackMeteors")}, FText(text))` on each player controller. The tag only picks the style; the text is yours. It replicates to the owning client, so players see it **without the mod** (Starfall). One at a time, about 2.4 s each: queue |
| A hint popup | build from the game's hint popup so frame, fonts and countdown match; check it is non-empty while invisible; fall back to your own card |
| A one-off status line | the themed message in [ui-construction](ui-construction.md) |

## Pitfalls

- Rebuilding rows on every open (crash). Build once.
- Sizing from measurement (crash and drift). Use fixed values or the game's own slots.
- Leaving a stale value in a pooled widget. Restore before dropping.
- Hiding something that feeds game logic (compass, original bars). Make it invisible, not gone.
- A viewport window for pad users. Dock it.

## Seen in

[sources/QuestLog.md](../sources/QuestLog.md), [sources/Slayer.md](../sources/Slayer.md), [sources/EnemyHPNumbers.md](../sources/EnemyHPNumbers.md), [sources/AurelianUI-Minimap.md](../sources/AurelianUI-Minimap.md), [sources/Starfall.md](../sources/Starfall.md).
