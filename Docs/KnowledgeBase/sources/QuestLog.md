# QuestLog 1.4.3: implementation guide

Source: `ue4ss/Mods/QuestLog/Scripts/main.lua` (3,690 lines), read in place (installed, not in `References/`). Author Maxxfilth. No
licence file: learn, do not copy.

**What it does:** every quest in the game in one window, including the 59 not yet started, with steps, distance, track and set-waypoint
buttons, a card beside the inventory, and full controller support. Read-only towards the game.

**Why read it:** it contains the most complete, working **recipes for adding to the pause menu**, **controller input**, **docking UI into
game screens**, and **reading quest data**. Several of these are shared across the author's mods (CollectionLog, Slayer, Mod Menu,
Storage Search), so the code comments describe them as "the same block in every mod".

## 1. Quest data

```lua
all = FindAllOf("QuestData")                          -- the game's own quest assets (59); skip Default__
q.QuestName:ToString()   q.QuestDescription:ToString()   q.QuestRegion   q.bIsMainQuest   q.bIsTaskQuest
q.InternalName:ToString()   q.bHideInQuestList   q.bShouldShowInCompletedQuestList
q.LinkedActivityID:ToString()   q.ActivityProgressOnCompletion
qp = pc.BP_Components_QuestProgress                   -- the player's quest component
st = qp:GetQuestState(q)                              -- not started / in progress / completed (numbers)
qp:GetCurrentObjectiveText(q, out)                    -- text in out.ObjectiveTextResult (out table convention)
qp.TrackedSecondaryQuest                              -- the tracked quest
qp.Quests                                             -- array of QuestProgress structs for touched quests:
                                                      --   Data, State, CurrentObjective, QuestInts, QuestBools{QuestBoolName,bQuestBoolValue}
```

Notes the author measured:
- Reading all 59 states takes about 1 ms; the `FindAllOf` takes about 50 ms, so cache the list.
- Quests share display names (First Steps x4, Rune Mysteries x3...), so sort by a **stable key** (asset name), "FindAllOf order is not".
- A save can hold the same quest twice (Rune Mysteries at state 2 and state 0): the entry with the **highest State wins**.
- Step order is **shipped as data in the mod** (`QUEST_STEPS`, generated offline from each quest's `ObjectiveTexts`), but the step **text** always comes
  from the game at runtime in the player's language (`GetObjectiveText`).
- Six `Quest_FTUE_Q*` assets are an unused second tutorial; hiding them stopped a finished player reading "48 of 54".
- The save names `QuestVariableName/Value`; the runtime names them `QuestBoolName/bQuestBoolValue`. Reading the runtime array covers co-op guests too.
- A handful of quests feed the game's activity tracker (`DomActivitySubsystem`, `LastPercentByActivity`, `CompletedActivities`).

## 2. Waypoint and map API

```lua
api = FindFirstOf("MapUIAPI")                         -- PlaceWaypoint, ClearWaypoint, IsShowingMap (verified 2026-09-20)
api:PlaceWaypoint({X=,Y=,Z=});  api:ClearWaypoint()
pc:GetMapCustomizationComponent().CurrentWaypoint     -- is one placed?
```

`PlaceWaypoint` round-trips through `Server_NotifyWaypointPlaced`, so it is **asynchronous**: `CurrentWaypoint` still reads invalid right after the call.
Never confirm from the return value; poll in the tick. Driving the game's own waypoint means the compass marker, distance and styling come free, and the
mod draws nothing. `followWaypoint` moves the waypoint when the quest's objective moves on.

## 3. Adding a button to the pause menu (shared block)

1. **Get the pause menu without a scan.** `NotifyOnNewObject("/Script/Dominion.PauseMenuScreen", cb)` where `cb` only appends to a list; plus one fallback
   `FindFirstOf("WBP_PauseMenuScreen_C")` shortly after Esc (a search is 35-50 ms). `usablePause` rejects `Default__` names; take the newest.
2. **Create a game-styled button.**
   ```lua
   LoadAsset("/Game/UI/Common/WBP_DomAllCapsButton")
   cls = StaticFindObject("/Game/UI/Common/WBP_DomAllCapsButton.WBP_DomAllCapsButton_C")
   b = WidgetBlueprintLibrary:Create(pc, cls, pc)
   b:SetStyle(like.Style); b:SetTextTransformPolicy(...); b.bCenterAlignText = ...; b.LeftAlignTextPadding = ...; b.bScrollText = ...   -- copy from pm.SettingsButton
   b:SetLabelText(FText("QUEST LOG"))
   ```
3. **Insert into `pm.VerticalBox_PauseMenu`.** The box holds the game's buttons (`ResumeButton`, `AgilityCourseSection`, `PlayerListButton`, `WorldDetails`,
   `SettingsButton`, `ExitToMainMenuButton`, `ExitToDesktopMenu`). All mod entries (ours and other mods') go **between SETTINGS and the exit buttons, sorted by label**
   so the order is the same every launch: remove extras and exits with `box:RemoveChild`, sort, re-add with `box:AddChildToVerticalBox`. A `menuHas(box, w)` check prevents
   duplicates; if it cannot confirm the button, the mod marks itself `broken` and uses a key instead.
4. **Re-check every few ticks** (`MENU.wait = 4`) because the menu is rebuilt; `fitPauseList(box)` grows the list so D-pad reaches every entry.
5. **Click handling:** `RegisterHook("/Script/CommonUI.CommonButtonBase:HandleButtonClicked", cb)`. `cb` only records `self:get():GetFullName()` into registries
   (`ROWS`, `TABS`, `NEXTREG`, ...); the work happens next tick. Opening: call `pm:Resume()` to close the pause menu first, then open the window one tick later
   (`pending = "open"` then `"open2"`).
6. If two mods add entries they coexist, because each reads the box and re-sorts.

## 4. Controller (pad) input, measured

**Problem:** a pad's A reaches `CommonButtonBase:HandleButtonClicked` from C++, so the UE4SS hook never fires. A *selectable* button does get selected.

**Recipe:**
```lua
b:SetIsSelectable(true)            -- only after the game has built the button
-- every tick:
if b:GetSelected() then  b:SetIsSelectable(false); b:SetIsSelectable(true)  -- clears the selection (SetIsSelected(false) is ignored on these buttons)
                         routeClick(fullName(b)) end
```
- A `PAD.seen` flag requires the selection to be seen on two polls for the entry button, so a mouse click (which selects too) is not mistaken for a pad press; a
  mouse click's hook pick wins and the selection is just cleared.
- **Navigation links:** `b:SetNavigationRuleExplicit(dir, target)` with `dir` 0 Left, 1 Right, 2 Up, 3 Down; and `b:SetNavigationRuleBase(dir, rule)`. Layout
  entry -> list rows -> footer; column and row ends link **to themselves**, otherwise focus leaves the window for a pause-menu entry. Hidden buttons are never linked.
- Scroll lists follow focus: `scroll:SetScrollWhenFocusChanges(1)`, `scroll:ForceVolatile(true)` (no stale rows after scrolling).
- Focus helpers: `widget:SetUserFocus(pc)`, `widget:SetKeyboardFocus()`; after closing the window refocus the pause entry.
- **A viewport window never gets pad input**, so for pads the window is a *second host* **docked inside the pause menu's canvas** (below).
- Inventory card: A is read by a 50 ms `IsInputKeyDown` sampler on the hovered or focused button (the game's own A takes the press there so selection never happens).

## 5. Docking UI into a game screen

```lua
root = pm.WidgetTree.RootWidget                         -- BackgroundBlur holding a CanvasPanel; use root:GetContent() if root is not a CanvasPanel
slot = canvas:AddChildToCanvas(frame)
slot:SetPosition({X=600,Y=170}); slot:SetSize({X=W,Y=H}); slot:SetZOrder(100)
frame:SetRenderTransformPivot({X=0,Y=0}); frame:SetRenderScale({X=0.9,Y=0.9})     -- fit the 1260 px window beside the list
```
- Built **once per pause menu**, then only shown and hidden ("rebuilding rows on every open is what crashed UE4SS in Collection Log").
- Only if `pm:IsActivated()` is true.
- **Inventory card:** docked into the inventory window's root canvas `WBP_Inventory_MainPanel_C` (found with `FindFirstOf`, rejecting `Default__` and names containing
  `:WidgetTree.` which are template copies). That canvas never hides, so the card follows `BackgroundPanel.BackgroundPanel` visibility (0 open, 1 closed); it steps aside when
  a processing station window is open. Panel frame chrome is 54 units, so slot size = content + 54.

## 6. One docked panel at a time across mods (`PauseDock`)

Shared variables: `PauseDock.owner` (string id) and `PauseDock.rev` (number). `DOCK.claim()` bumps `rev` and writes `owner = DOCK.ID`; `DOCK.lost()` returns true if the
revision moved and the owner is someone else; the mod then closes itself. If the shared write fails it does not close itself on a stale read.

## 7. Keeping the keyboard working in a UI window (click guard)

To open a window with mouse cursor but still see menu keys and Esc on the game thread, the mod builds an **input mapping context** and adds it with a high priority so game
clicks are consumed:
```lua
imc = StaticConstructObject(StaticFindObject("/Script/EnhancedInput.InputMappingContext"), gameInstance)
ia  = StaticConstructObject(StaticFindObject("/Script/EnhancedInput.InputAction"), gameInstance);  ia.bConsumeInput = true
imc:MapKey(ia, { KeyName = FName("LeftMouseButton") }) ...
sub = FindAllOf("EnhancedInputLocalPlayerSubsystem")[...]      -- once per world
sub:AddMappingContext(imc, priority, {});   -- later:  sub:RemoveMappingContext(imc, {})
```
The shape of `MapKey` is verified by reading its property names with `fn:ForEachProperty` before use (`Action`, `ToKey`); if it does not match, the guard is `broken`.
Input mode: `wbl:SetInputMode_GameAndUIEx(pc, focusWidget, 0, false, false)` with the guard, else `SetInputMode_UIOnlyEx(pc, focusWidget, 0, false)`; `pc.bShowMouseCursor = on`.

## 8. Reusable recipes

| Need | Take this |
|---|---|
| Pause-menu entry | sections 3 and 6 |
| Controller support | section 4 (selectable buttons, `GetSelected` polling, explicit navigation) |
| Window inside a game screen | section 5 |
| Read quest status | section 1 |
| Drive the game's own waypoint | section 2 |
| Keep Esc and keys working with a cursor | section 7 |
| Stable ordering of game data | sort on asset name, not `FindAllOf` order |

## Cautions

- All verified in game on the author's 1.0 build, 2026-09-16 to 2026-10-06.
- The "same block in every mod" comment means this pause-menu code is a de facto standard among this author's mods; matching its sort order keeps our entries compatible.
