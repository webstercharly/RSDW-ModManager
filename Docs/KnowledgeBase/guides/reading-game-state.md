# Guide: reading game state (health, quests, items, skills, kills, unlocks, targets, saves)

**Use this when** a mod needs to know something about the player, enemies, world nodes or progress, and show or react to it.

Everything here was verified in game by its author unless marked. Class and field names are exact.

## Health, stamina and other attributes

**`HealthComponent.AuthoritativeHealth` and `.MaxHealth` are dead mirrors**: they never move when an enemy is damaged (30.0 stays 30.0; max reads 0.0). Use:

```lua
local lib = StaticFindObject("/Script/Dominion.Default__AttributeFunctionLibrary")
local hp, mx = StaticFindObject("/Script/Dominion.HealthAttribute"), StaticFindObject("/Script/Dominion.MaxHealthAttribute")
local out = {}; lib:BP_TryGetFloatAttributeValue(char, hp, -1.0, out, {})
-- found = out.OutbFound; value = out.OutAttributeValue (all outs land in the first table)
```

or the drawn fraction `healthBarWidget.VitalFillValue` (0..1, cannot be wrong because it is drawn; `VitalBarValue` is not the fill). `VitalFillValue` **freezes at death**, so re-verify against the attribute about once a second. Other attribute classes: `StaticFindObject("/Script/Dominion."..name)` (for example `DA_Attribute_SpecialCharge`; an earlier match on "special" read the wrong attribute). Player vitals widget: `PlayerVitalsWidget` with bars `HealthBar`, stamina, special.

Attribute storage (RSDWTools): `UDominionAttributesComponent.FloatAttributes` (what each slot is) parallel to `AttributeValues` (live floats), plus `Shared...`; identify a slot by its runtime class name.

## Enemies

- Enumerate through `FindAllOf("AiHealthBarComponent")`: `comp.AICharacter`, `comp.HealthComponent` (about 47 ms; scan every 3 s).
- Boss bars are HUD widget `WBP_AI_Boss_Healthbar_C`, not a world bar.
- Weaknesses: `AIAttributesComponent.DamageTypeAffinities` (TMap of `GameplayTag -> 0 weak / 1 resist / 2 immune`), cached **per Blueprint class**. Tags like `DamageType.Physical.Crush` (depth 3 is a type, depth 2 a class). Per-type float attributes cannot tell weak from resist.
- Power level: `char.PowerLevel`. Class name: `char:GetClass():GetFName():ToString()`.
- Death: hook `BP_OnDeath`; credit via `char:GetController().ThreatSystem.DamageInstigators:ForEach(...)` comparing to the player's pawn name.
- Kills ever made: the character save's `KilledOnceAIs` (below).

## Quests

```lua
local qp = pc.BP_Components_QuestProgress
for _, q in ipairs(FindAllOf("QuestData")) do ... end                -- 59 quests; sort by asset name (FindAllOf order is not stable)
q.QuestName:ToString(); q.QuestDescription:ToString(); q.QuestRegion; q.bIsMainQuest; q.bIsTaskQuest; q.InternalName:ToString()
q.bHideInQuestList; q.bShouldShowInCompletedQuestList; q.LinkedActivityID:ToString(); q.ActivityProgressOnCompletion
qp:GetQuestState(q)                        -- number: not started / in progress / completed
qp:GetCurrentObjectiveText(q, out)         -- out.ObjectiveTextResult
qp.TrackedSecondaryQuest
qp.Quests                                  -- QuestProgress structs: Data, State, CurrentObjective, QuestInts, QuestBools{QuestBoolName, bQuestBoolValue}
```

Reading all 59 takes about 1 ms. A save can hold a quest twice; take the highest `State`. Hide placeholder entries (`[PH]` names) and the unused `Quest_FTUE_Q*` tutorial. Quest saves store `PersistenceID`, not names.

Quest markers and distance: the minimap/compass icons ([map-and-minimap](map-and-minimap.md)); `qp:OnRep_VisibilityTrackers({})` re-sends markers.

## Items and inventory

- Components on the controller: `pc.BP_Components_Inventory` (bag), `BP_Components_Loadout` (equipped; **slot 7 is the right hand**), `BP_Components_PersonalInventory` (storage), `BP_Components_InventoryController`.
- `inv:GetItemFromSlot(i).ItemData`; name `ItemData:GetFName():ToString()` (patterns: `ITEM_Pickaxe_`, `ITEM_Logging_Axe_`, `ITEM_Spade_`, `ITEM_WateringCan_`, `ITEM_Bucket_Compost`, `ITEM_FishingRod_`, `ITEM_FishingNet_`); `ItemData.PowerLevel` ranks tiers (untiered = -1); `inv.MaxSlotCount` (152).
- Ever picked up: `pc.ProgressComponent:HasPickedUpItem(itemData)` (about 0.06 s for the whole catalog: slice it).
- Unlocks: `prog:IsRecipeUnlocked(o)`, `IsBuildingUnlocked(o)`, `IsSpellUnlocked(o)`, `JournalFunctionLibrary:IsJournalEntryUnlocked(o, pc)`. Catalog classes: `ItemData`, `RecipeData` (1,218), `BuildingPieceData` (856), `DominionSpellData` (95, only entries with `SpellDisplayName` are player spells), `JournalEntryData` (1,315). `FindAllOf` returns derived classes: do not scan subclasses too.
- Held item: loadout slot 7; `GetHeldEquipmentDataRight` returns nothing on this build.
- Dropped items: `FindAllOf("RuntimeSpawnedWorldItem")`; `w.ItemData`, `w.MagneticComponentGrantItem` (`HasTarget()`, `bHasBeenGranted`, `bAutoMagnetizationEnabled`), `w.LaunchableComponent.bLaunched`; variants `_NoExpiry_` and `_ProcessingStation_` have different full-name prefixes.

## Skills and XP

`pc.SkillComponent` (fallback `GetPlayerSkillComponent()`); `comp.Skills` array of `{CurrentXP,...}`; skill assets `SKILL_*`; XP table `DT_XPEvents_Mining`. Poll totals once a second (the XP hook misses native XP). Curve: level 99 = 1,000,000 XP.

## What the player is facing and near

- Interaction target: `pawn:GetComponentByClass(InteractableDetectorComponent).CurrentWorldActor` (trees, plots, interactables; **not** rocks or ore, may hold a dead handle, reports water and not the fishing spot).
- Position scan fallback: list nodes by class within 30 m, accept those within about 70 degrees of `pc:GetControlRotation().Yaw` (dot product > 0.34), score `distance * (2 - facing)`.
- Classes: rocks `DestructibleWorldActor` + `OreNode` (geysers have neither word in the name), trees `FellableTree` + `TreeLog`, fishing `FishingNodeV2` (class contains `_Rod_` or `_Net_`), buried chest class containing `BuriedChest` (`DigChargesRequired/Applied`).
- Resource nodes: `ResourceRespawnComponent` (every ore, tree, plant): `ResourcesAvailable`, `GetQuantityAvailable()`, `SpawnSettings...RespawnDuration`. Mined-out nodes remain depleted until the area reloads.
- Farm plots: `FarmSlotComponent`: `GetSoilState()` (0 weeds, 1 tilled), `IsFullyWatered()`, `IsFullyFertilized()`, `CanHarvest()`, `CanHealDisease()`, `CanRapidGrow()`, `ShouldVisualizeGrowthLock()`, `PlantMeshComponent:IsVisible()`, `bIsRegistered`. Read a plot only once registered.
- Time: `InGameTimeActor`; one in-game day is 24 real minutes.
- Persistence layer: `PersistenceSubsystem`; world and game state: `GameStateBase`, `GameInstance`.

## Reading the character save offline

When a runtime route is missing, read the save file **as text, read-only**:

```lua
local text = f:read("*a")
local list = text:match('"KilledOnceAIs"%s*:%s*%[(.-)%]')            -- then list:gmatch('"([^"]+)"')
local guid = text:match('"char_guid"%s*:%s*"(%x+)"')
```

Path: `%LOCALAPPDATA%\RSDragonwilds\Saved\` (character files). The save may be absent on a co-op client: say so in the UI. Never write to it.

## Identity and multiplayer

- Local controller: `IsLocalController()`, host: `HasAuthority()`, character name `pc.PlayerState:GetPlayerName():ToString()`.
- Key per-character files by name plus `char_guid` (names can be reused after deleting a character; non-ASCII names need a hash suffix).
- Component availability differs on co-op clients (`ProgressComponent` may be nil): treat nil as "try later".
- Roster: `UEHelpers.GetAllPlayerStates()` / `GetAllPlayers()`.

## Reading cheaply

One drawn-value float as a change detector, expensive calls only when it moves; caches keyed per class; slices for big catalogs; scans on long intervals ([performance](performance.md)).

## Seen in

[sources/EnemyHPNumbers.md](../sources/EnemyHPNumbers.md), [sources/QuestLog.md](../sources/QuestLog.md), [sources/CollectionLog.md](../sources/CollectionLog.md), [sources/AutoTool.md](../sources/AutoTool.md), [sources/NoAutoPickup.md](../sources/NoAutoPickup.md), [sources/Slayer.md](../sources/Slayer.md).
