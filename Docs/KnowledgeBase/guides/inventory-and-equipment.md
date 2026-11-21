# Guide: inventory, equipment and items

**Use this when** a mod grants, finds, equips, swaps or tracks items.

The shell's `rlm_inventory.lua` and the Hot Swap module's `rlm_swaps.lua` already do much of this for gear swaps; use this guide to cross-check approaches.

## Where items live

| Property on the controller | Holds |
|---|---|
| `BP_Components_Inventory` | backpack (`MaxSlotCount` 152) |
| `BP_Components_Loadout` | equipment and quick slots (**slot 7 = right hand**) |
| `BP_Components_PersonalInventory` | personal storage |
| `BP_Components_InventoryController` | the object that performs inventory actions |

Read a slot: `inv:GetItemFromSlot(i)` then `.ItemData`; name `ItemData:GetFName():ToString()`.

## Find the best item of a kind

AutoTool: match the asset name by prefix, rank by `ItemData.PowerLevel` (untiered items report -1), lowest slot on a tie.

| Kind | Name prefix |
|---|---|
| axe | `ITEM_Logging_Axe_` |
| pickaxe | `ITEM_Pickaxe_` |
| spade | `ITEM_Spade_` |
| watering can | `ITEM_WateringCan_` |
| compost | `ITEM_Bucket_Compost` |
| rod / net | `ITEM_FishingRod_` / `ITEM_FishingNet_` |

## Equip and use

```lua
ctl = pc.BP_Components_InventoryController
ctl:UseItemFromInventory(bag, slot)       -- the same call the hotbar keys make
```

- It swaps directly (axe to pickaxe with no empty hand) and **toggles**: using the item already held puts it away. Only call it for an item of a different kind, and guard a double press (0.4 s).
- RSDWTools' gear swap uses this normal inventory-use / server RPC path (not a developer equip command): changed slots are dispatched as a **batch at about 70 ms cadence**, then the full target is **replication-verified twice**. No rollback batch during combat; a partial result is left alone and the press can be repeated. An existing-item-only rule means the swap aborts if any selected item is missing and never generates or drops gear.

## Give items

| Route | Call | Notes |
|---|---|---|
| Slayer ("Dev Menu's proven route") | `inv:CanAddItemByData(item, count)` then `inv:AddItemByData(item, count, 100.0, {})` | check room first; keep the reward if there is none |
| RSDWTools | resolve the item by name, then insert | see below |

Resolve an item or recipe by asset short name:
1. `FindFirstOf(name)` (a live object or CDO),
2. `AssetRegistry:GetAssetsByClass({ItemData, RecipeData})` sweep, cached `asset_name -> package_name` (subclasses included); on a miss re-sweep once,
3. `LoadAsset(package)` then `StaticFindObject(package.."."..name)`.

## Pull dropped items

See [tuning-game-data](tuning-game-data.md) (`MagnetRange`, `BP_MagnetizeToPlayer`) and [reading-game-state](reading-game-state.md) for the world item fields.

## Track what the player has had

`pc.ProgressComponent:HasPickedUpItem(item)` is the game's own record. CollectionLog also watches bag, worn gear and storage once a second and records dated first-obtained lines. Walk the catalog in slices (the whole list takes about 0.06 s).

## UI over inventory slots

RSDWTools' selection mode tints inventory slots and uses middle-click to toggle items; the scan runs **only in selection mode** and is removed afterwards ("avoiding any inventory-widget scanning during normal gameplay or combat"). QuestLog docks a card into `WBP_Inventory_MainPanel_C` ([extending-game-ui](extending-game-ui.md)); sample `IsInputKeyDown` at 50 ms on its buttons because the game's own A takes the press there.

## Pitfalls

- `InventoryController:UseItemFromInventory` is a toggle.
- Items with an empty `Data` struct crash the game's own tile code.
- `DropItemFromInventory` and `ItemsToDrop` crashed NoAutoPickup's probe.
- Restoring items must never drop them on the floor; a full bag is an error, not a drop.
- Item display names need cleaning from asset names; use the game's data for real text.

## Seen in

[sources/AutoTool.md](../sources/AutoTool.md), [sources/Slayer.md](../sources/Slayer.md), [sources/RSDWTools.md](../sources/RSDWTools.md), [sources/CollectionLog.md](../sources/CollectionLog.md), [sources/NoAutoPickup.md](../sources/NoAutoPickup.md).
