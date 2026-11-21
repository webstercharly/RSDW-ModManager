# Game API catalogue

Things other mods have hooked, read or called. Names are exactly as seen in their
source. Confidence: *Measured* = the author says they tested it, *Observed* = seen
in code only. None of this has been re-verified on our build unless it says so.

Sources are abbreviated: AUI AurelianUI, MM MapMarkers, PF PenguinFinder,
RA ResourceAtlas, NAP NoAutoPickup, AT AutoTool, FS FishingSliders, SL Slayer,
SP SkillPets, SF Starfall, CS Class Specialisations, RS RuneSchema,
RT RSDWTools (third-party, installed beside this project).

## Hook targets seen

| Target | Fires | Used by |
|---|---|---|
| `/Game/Gameplay/AI/BP_DominionAICharacter.BP_DominionAICharacter_C:BP_OnDeath` | once per creature death; not on unload or player death | SL |
| `/Script/Dominion.PlayerInteractionManager:Multicast_AcknowledgeInteractionRequest` | once per E press; argument is the NPC's interaction component, owner is the NPC | SL, SP |
| `/Script/CommonConversationRuntime.ConversationParticipantComponent:ServerAdvanceConversation` | dialogue advanced | SP |
| `/Script/CommonUI.CommonButtonBase:HandleButtonClicked` | any button click (mouse only, not pad) | SL |
| `/Game/UI/Map/WBP_TopNav_Map.WBP_TopNav_Map_C:BP_OnMapMaximised` / `BP_OnMapMinimised` | map opened / closed | PF |
| `/Script/Dominion.MapCustomizationComponent:Client_NotifyPinsSet` | pins loaded on client | PF |
| `/Script/Dominion.MapCustomizationComponent:Server_NotifyPinPlaced` / `Server_NotifyPinCleared` | pin placed / cleared | PF |
| `/Script/Dominion.LocalPlayerAudioSubsystem:HandleMapPinAdded` / `HandleMapPinRemoved` | local pin events | PF |
| `/Script/Dominion.QuestProgressComponent:Client_NotifyTrackedQuestLoaded` | tracked quest message; arrives before the tracker widget exists | AUI |
| `/Script/Dominion.LorePopupUIAPI:OpenLorePopup` | lore popup opened | AUI |
| `/Script/Dominion.Skills2MainScreen:OnEntryWidgetCreated`, `OnIntroAnimationFinished`, `OnSkillTileClicked`, `OnSkillTileSelected` | Skills screen events | SL |
| `/Script/Dominion.PlayerMeleeAttackComponent:Multicast_SendDamageCacheData` | melee hit | SF |
| `/Game/Gameplay/UtilityMagic/PerkSpells/DivineRock/BP_DivineRockBase.BP_DivineRockBase_C:GetDisplayName` | name shown for a rock actor | SF |

Hook-free alternatives: FS and AT poll components instead (see stability-rules rule 9).

RT notes that `/Script/Engine.PlayerController:InputAxis` is a native function,
not a UFunction, so `RegisterHook` on it fails ("no UFunction with the specified
name was found"). Hooks only work on reflected UFunctions. *Measured (RT).*

## NotifyOnNewObject classes

`/Script/Dominion.MapCustomizationComponent` (MM), `InteractableNPC` (SL),
`PauseMenuScreen` (SL), `Skills2MainScreen` (SL), `CraftingMenuBase`,
`CraftingUIAPI`, `InventorySlotBase`, `TopBarMenu_InGame`, `PlayerVitalsWidget`,
`ReticleWidgetBase`, `DominionSpellActor`, `GroundedExplodingProjectile`,
`HuntersSenseEffectInstance`, `TempestShieldGameplayEffectInstance` (CS),
`/Script/Engine.GameEngine` (CS).

## FindFirstOf / FindAllOf classes

`DominionPlayerController`, `GameInstance`, `GameStateBase`, `PersistenceSubsystem`,
`HUDUISubsystem`, `InGameTimeActor`, `MapUIAPI`, `MapIconComponent`,
`CompassWidget`, `FarmSlotComponent`, `FarmPlantDataAsset`,
`ResourceRespawnComponent`, `RuntimeSpawnedWorldItem`, `WBP_DominionMinimap_C`,
`WBP_TopNav_Map_C`, `WBP_TutorialNotifications_Item_C`,
`BP_Components_QuestProgress_C`, `BPC_RuneSchemaRegistryBridge_C`, `UserWidget`.

## Static libraries reached with StaticFindObject

`/Script/UMG.Default__WidgetBlueprintLibrary`, `Default__WidgetLayoutLibrary`,
`Default__SlateBlueprintLibrary`, `/Script/Engine.Default__GameplayStatics`,
`Default__KismetSystemLibrary`, `Default__KismetMathLibrary`,
`Default__KismetTextLibrary`, `Default__KismetRenderingLibrary`,
`Default__KismetMaterialLibrary`, `Default__InputSettings`,
`/Script/AssetRegistry.Default__AssetRegistryHelpers`,
`/Script/Niagara.Default__NiagaraFunctionLibrary`. Minimap plugin classes:
`/Script/MinimapPlugin.MapViewComponent`, `MapIconComponent`.

## Components, fields and calls

**Inventory and items**
- `pc.BP_Components_Inventory:AddItemByData` is "Dev Menu's proven route" for
  granting items (SL).
- `InventoryController:UseItemFromInventory(bag, slot)` is what hotbar keys do. It
  swaps equipment directly and **toggles**: using the item already held puts it
  away. Right-hand held item is loadout slot 7; `GetHeldEquipmentDataRight`
  returned nothing on this build (AT, *Measured*).
- `ItemMagnet.MagnetRange` on the player (350 cm default) controls pull-in distance;
  range 2000 collected everything (NAP, *Measured* 2026-10-01).
- Dropped loot is `BP_RuntimeSpawnedWorldItem_C`; its `MagneticComponent` can pull
  an item itself. Enemy loot lands 14-26 uu from the corpse, node drops 21-316 uu
  from the node (NAP).
- RT resolves item and recipe assets by short name: `FindFirstOf(name)`, then an
  `AssetRegistry:GetAssetsByClass({ItemData, RecipeData})` sweep cached as
  `asset_name -> package_name`, then `LoadAsset(package)` and
  `StaticFindObject(package.."."..name)`. Re-sweep once on a miss. *Observed.*

**Skills and XP**
- RT: player's `SkillComponent` (fallback `GetPlayerSkillComponent()`); `comp.Skills`
  is `TArray<FSkill>` with a `CurrentXP` field. After raising level call
  `SkillPerkComponent:HandleSkillLevelIncreased` so perks and unlocks fire. *Observed.*
- SP and SL read skill XP totals once a second; SP says the XP-gain hook misses
  native XP. SL XP curve: 99 = 1,000,000 XP.
- `KilledOnceAIs` in the character save lists creatures killed (SL reads it offline,
  read-only).

**Attributes and effects**
- RT: attributes live in two parallel arrays on `UDominionAttributesComponent`:
  `FloatAttributes` (what each slot is) with `AttributeValues` (the live floats),
  plus `SharedFloatAttributes` / `SharedAttributeValues`. The live values are the
  float arrays. *Observed.*
- RT: effects go through `UDominionGameplayEffectsComponent:InstantiateGameplayEffect(
  DataClass, InstigatingGE, bForceNewInstance)` then `ApplyGameplayEffect(Instigator,
  Source, Handle, bIgnoreChanceToApply)`, with a matching `RemoveGameplayEffect`.
  Described as the authoritative path for attribute changes. *Observed.*
- AUI reads `DA_Attribute_SpecialCharge` for the blue bar; an earlier pick matched an
  unrelated "special" attribute.

**Map**
- Pins: `MapCustomizationComponent.MaxNumberOfPins` (99). Save layout
  `GameProgress.MapCustomization.Pins` = `PinType` 0-5 + x,y. See 05.
- Drawn pins are `MapIconComponent`s on the `MinimapPluginMapIcons` actor, with
  `SetIconTexture` and `SetIconDrawColor` redrawing at once (MM, *Measured*).

**Farming and resources**
- AT: `FarmSlotComponent:GetSoilState()` (0 = weeds), `IsFullyWatered()`,
  `IsFullyFertilized()`, `CanHarvest()`, `CanHealDisease()`.
- RA: read a plot only when its slot's `bIsRegistered` is true.
- `ResourceRespawnComponent.ResourcesAvailable`, `SetResourceAmount(n)`,
  `PauseRespawning`, `ResumeRespawning` (AT, FS). Every ore node, tree and plant has
  one.
- FS: `BiteTimerMin/Max` on the fish controller class default object, read when the
  controller spawns at the cast; fight drain rates on
  `BP_CatchableFishController_C:BP_Fishing_Combat_GEN_VARIABLE`; `ChanceOfJunk` on every
  `CFSD_*` species asset; `SpellModule_NetFishing.FishingProbabilityPerLevelDifferences`.

**Interaction**
- `InteractableDetectorComponent.CurrentWorldActor` is the facing target for trees,
  plots and other interactables. Rocks and ore nodes never become the target (AT).
- SP rides on `BP_InteractablePlayerTeleporter` stripped bare to get the game's own
  E prompt.

**Multiplayer**
- RT: `IsPlayerControlled()` is true for any human-driven pawn, local or remote. A
  loop using it returned another player's controller. Use `APlayerController:
  IsLocalController()` as the ground truth. *Measured (RT).*
- Most gameplay mods run on host or solo only; several expose `AllowAsClient`.

**World settings**
- RT: Advanced Settings rows are `UDifficultySettingData` with `PlayerAdjustable`
  (`Never 0 / OnlyCustom 1 / CustomAndCreative 2 / AllModes 3`) and
  `bCanBeChangedAfterWorldCreation`. The widget has no per-mode special casing, so
  setting every loaded one to 3/true lights up all options. *Observed.*

**Other**
- `AWorldEventManager:GetWorldEventManagerInstance` and `StartEvent(TSoftClassPtr<
  AWorldEvent>, FTransform, players, FGameplayTag)` (RT probes, confirm-gated).
- Quest saves store `QuestData.PersistenceID`, not names; RT dumps the catalogue so
  an offline audit can map IDs back to assets.
- Console: `KismetSystemLibrary::ExecuteConsoleCommand` works. Bare
  `APlayerController::ConsoleCommand` trapped with "UObject instance is nullptr"
  because it is a plain C++ method, not a UFunction (RT, *Measured*).
- `Help`, `DumpConsoleCommands`, `DumpConsoleVariables` console commands list every
  CVar (RT).
