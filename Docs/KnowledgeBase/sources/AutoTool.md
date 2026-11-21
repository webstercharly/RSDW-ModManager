# AutoTool 1.0.3: implementation guide

Source: `References/OnlineMods/AutoTool/1.0.3/extracted/AutoTool/Scripts/main.lua` (720 lines).
No licence stated: learn, do not copy.

**What it does:** one key press puts the right tool in the player's hand for whatever they are
facing: pickaxe for rocks, axe for trees and logs, spade for weeds, dead crops and buried chests,
watering can or compost bucket for farm plots, rod or net for fishing spots.

**Why read it:** it solves three hard problems with no hooks: working out what the player is
looking at, choosing the best item in a bag, and showing a message with the game's own panel style.

## Flow of one key press

```text
RegisterKeyBind -> sets REQ.work = true            (callback does nothing else)
100 ms game-thread tick:
   wait until world ready (10 s after pawn exists)
   ignore if a menu is open (pc.bShowMouseCursor)
   faced()      -> (actor, kind)
   family       -> kind->tool, or plotFamily() for farms
   ensureTool() -> bestSlot() -> InventoryController:UseItemFromInventory(bag, slot)
   showMessage()
```

## 1. What is the player facing?

Two sources, tried in order:

**A. The game's interaction target.**
`pawn:GetComponentByClass(InteractableDetectorComponent)` then `.CurrentWorldActor`. Covers farm
plots, standing trees and fishing nodes when they become the target. Always `IsValid` first: "the
target can hold a dead handle".

**B. Position scan.** Needed because the target never reports rocks or ore, loses a tree to any
branch next to it, never reports felled logs, and reports the water and not the fishing spot.

```text
nodeList(kind): FindAllOf of a class, keep those within 30 m (3000 uu), cached;
                rebuilt only when the player moved 8 m (800 uu) or 20 s passed
                (a FindAllOf costs about 50-60 ms)
nodeInFront(): range = RockRange*100 (rocks, trees) or 2000 (fishing, a rod reaches ~20 m)
               facing = dot(unit vector to node, forward from pc:GetControlRotation().Yaw)
               accept facing > 0.34 (about 70 degrees), score = distance * (2 - facing), lowest wins
```

Classes scanned per kind: rock `DestructibleWorldActor` plus `OreNode` (ore nodes and rune essence
geysers do not derive from `DestructibleWorldActor`); tree `FellableTree` plus `TreeLog`;
fish `FishingNodeV2`. A class name test (`MiningRock`, `OreNode`, `Rock`, `RuneEssenceGeyser`,
`SplittableLog`, `FishingNode`, `_Net_`) classifies an actor.

Trees emptied by the player are skipped via `ResourceRespawnComponent.ResourcesAvailable <= 0`
(nodes are never destroyed when mined out, only depleted until the area reloads).

Buried chests: class contains `BuriedChest`; needs a spade while `DigChargesApplied <
DigChargesRequired`.

## 2. Which tool does a farm plot want?

`FarmSlotComponent` found by `actor:GetComponentByClass`. Decision order (`plotFamily`):

1. `GetSoilState() == 0` -> spade (weeds).
2. `CanHarvest()` or `CanHealDisease()` -> no tool; the player presses E.
3. Soil state 1 (tilled) and `PlantMeshComponent:IsVisible()`:
   - not visible: needs a seed, no tool.
   - visible and `CanRapidGrow() == false` and `ShouldVisualizeGrowthLock() == false`:
     dead crop, dig it out with the spade.
4. `IsFullyWatered() == false` and a watering can exists -> water.
5. Optional: `IsFullyFertilized() == false` and compost bucket exists -> compost.

Every call goes through `call(o, name)` which `IsValid`-checks then `pcall`s `o[name](o)`.

## 3. Choosing the item

Items are matched by **asset-name pattern**, read off the shipped containers:

| Family | Pattern |
|---|---|
| axe | `ITEM_Logging_Axe_` |
| pickaxe | `ITEM_Pickaxe_` |
| spade | `ITEM_Spade_` |
| watering can | `ITEM_WateringCan_` |
| compost | `ITEM_Bucket_Compost` |
| rod | `ITEM_FishingRod_` |
| net | `ITEM_FishingNet_` |

- Backpack: `pc.BP_Components_Inventory`, slot count `MaxSlotCount` (152),
  `inv:GetItemFromSlot(i).ItemData`, name from `ItemData:GetFName():ToString()`.
- Best = highest `ItemData.PowerLevel`, lowest slot on a tie. Untiered items report -1.
- Held item: `pc.BP_Components_Loadout` slot **7** is the right hand.
- Equip: `pc.BP_Components_InventoryController:UseItemFromInventory(bag, slot)`. It **toggles**, so
  it is only called when the held item is a different family. A 0.4 s guard stops a double press
  re-toggling during the switch.
- Mounted or not on foot: `pawn` class name must contain `PlayerCharacter`.

## 4. On-screen message without crashing

`showMessage(pc, head, body, seconds)` builds one reusable panel with the game's own look:

```lua
LoadAsset("/Game/UI/Panels/WBP_Panel");  LoadAsset("/Game/UI/Common/WBP_DomTextBlock")
panelC = StaticFindObject(pkg .. "." .. assetName .. "_C")
frame  = WidgetBlueprintLibrary:Create(pc, panelC, pc)
vb     = StaticConstructObject(/Script/UMG.VerticalBox, frame.WidgetTree)
frame.PanelContent:AddChild(vb)
text   = StaticConstructObject(WBP_DomTextBlock_C, tree); text:SetFont / SetColorAndOpacity / SetText(FText(s))
slot   = vb:AddChildToVerticalBox(text); slot:SetPadding({Left=18, Top=0, Right=18, Bottom=2})
frame:AddToViewport(700)
frame:SetPositionInViewport({X, Y}, false); frame:SetDesiredSizeInViewport({X=w, Y=h})
frame:SetVisibility(3)   -- HitTestInvisible: shown, never takes clicks;  1 = collapsed
```

Hard-won details:
- The game panel includes a `NiagaraSystemWidget` ember effect that traces a phantom box on custom
  panels. Walk `frame.WidgetTree.RootWidget` (depth limit 10) and `SetVisibility(1)` on it. *Proven
  in game 2026-09-30 by the author.*
- Panel background at 80% opacity via `frame.BackgroundPanel:SetRenderOpacity(0.8)`.
- Indent with slot padding, not spaces: a space differs in width across font sizes.
- Size to content: `vb:ForceLayoutPrepass()` then `vb:GetDesiredSize()`; the panel chrome adds 54
  units each way, so a fixed height ran the text over the border.
- Viewport size: `WidgetLayoutLibrary:GetViewportSize(pc) / GetViewportScale(pc)`.
- Build once per world and only show/hide after. If the build fails once for a controller it is
  never retried in that world (`msgFailedFor`).
- On world change the stale widget is **dropped, never called**.

## 5. Config and Mod Menu

Identical shape to the other Lua mods here: `config.txt` parser (typed from the defaults in `cfg`),
`MM_LIVE` list for keys applied live, `WorkKey` bound at boot via `Key[name:upper()]` and
`RegisterKeyBind`. A key change from Mod Menu cannot rebind live (no unregister), so it logs and
shows an on-screen "works after a game restart" message. The comment warns that a key missing from
`MM_LIVE` is a toggle that silently does nothing.

## Reusable recipes

| Need | Take this |
|---|---|
| Known-class lookup | `StaticFindObject("/Script/Dominion.X")` cached, then `pawn:GetComponentByClass(cls)` |
| Item matching | name-pattern per family, rank by `PowerLevel` |
| Facing detection fallback | forward vector from `GetControlRotation().Yaw`, dot product cone |
| Throttled world scans | cache list, rebuild on 8 m move or 20 s |
| Themed popup panel | game `WBP_Panel` + `WBP_DomTextBlock`, kill the Niagara ember |
| Guarding every call | `call(o, fn)` wrapper: valid, pcall, nil on failure |

## Cautions

- Probe dates 2026-09-26 to 2026-10-20; the author notes several "no X on this build" findings
  (`GetHeldEquipmentDataRight` returns nothing).
- Holds a dead-handle rule from four crashes; the wrapper pattern above is the fix.
