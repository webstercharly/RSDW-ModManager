# Skill Pets 1.0.1: implementation guide

Source: `References/OnlineMods/SkillPets/1.0.1/extracted/RSDragonwilds/Binaries/Win64/ue4ss/Mods/SkillPets/Scripts/`
(`main.lua` 2,559 lines, `talk.lua`, `looks.lua`, `behaviors.lua`) plus four `~mods` paks. No licence stated:
learn, do not copy. Note the archive keeps game-root paths (`RSDragonwilds/...`).

**What it does:** one rare pet per skill, spawned only on the player's machine, follows and reacts.

**Why read it:** the only reference for **spawning and moving local-only actors**, using **your own meshes from a
pak**, **leader-pose skinned meshes**, and the **UE4SS registry leak** workaround.

## Pet bodies, five routes with fallbacks

| Kind | Actor | How |
|---|---|---|
| `static` | `StaticMeshActor` | `StaticMeshComponent:SetStaticMesh(mesh)`; the simplest, proven route |
| `npc` | a game `BP_NPC*` class | game's own anim; strip talk and collision |
| `skel` | `SkeletalMeshActor` with a creature mesh | plays the creature's anims |
| `mesh` | own static mesh from pak | hops like a prop |
| `skin` | own skinned mesh posed by a hidden game creature | leader pose |

Any failure in a creature route marks `ROUTE_FAIL[kind]` for the session and falls back to the row's static
prop, so a pet is always shown.

## Spawning an actor: deferred spawn

```lua
gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
raw = gs:BeginDeferredActorSpawnFromClass(pawn, cls, xf, 2, nil, 0)   -- 2 = always spawn; owner nil
a = raw:get() or raw
a.bSkipSpudStore = true                  -- never written into the world save
-- configure BEFORE it finishes spawning
gs:FinishSpawningActor(a, xf, 0)
```

`xf` is `{Rotation={X,Y,Z,W}, Translation={X,Y,Z}, Scale3D={X,Y,Z}}`. Deferred spawn lets the code set mobility,
meshes and properties before construction scripts run. A `before(a)` callback returns false to abort and destroy.

## Configuring the body

Static: `c:SetMobility(2)` (Movable), `c:SetCollisionProfileName(FName("NoCollision"), true)`,
`c:SetCollisionEnabled(0)`, `c:SetCanEverAffectNavigation(false)`, `c:SetStaticMesh(mesh)`.

NPC: set `x.DisplayName = FText(name)`, `a:K2_GetRootComponent():SetMobility(2)`, destroy its
`/Script/Dominion.InteractionComponent`s (so its own talk prompt goes), disable collision on every
`/Script/Engine.PrimitiveComponent`; animate through `a.Mesh`.

Skeletal: try in order `SetSkeletalMeshAsset(mesh)`, `SetSkinnedAssetAndUpdate(mesh, true)`,
`SetSkeletalMesh(mesh, true)`; destroy the actor if all refuse.

Leader-pose skin: spawn the creature actor as `lead`, add a second `SkeletalMeshComponent` with
`a:AddComponentByClass(skc, false, ident(), false)`, set the pak mesh, then
`fc:SetLeaderPoseComponent(lead, true, false)` and hide the leader (`SetHiddenInGame(true,false)` or
`SetRenderInMainPass(false)`/`SetRenderInDepthPass(false)`/`SetCastShadow(false)`, or `SetVisibility(false,false)`).
`VisibilityBasedAnimTickOption = 0` keeps it animating while hidden. The leader has **no anim instance**: reading
through that null handle crashed the game.

Attach parts: `comp:K2_AttachToComponent(parent, FName(bone), 1, 1, 1, false)`.

Scale: `a:SetActorScale3D({X=s,Y=s,Z=s})`. Materials: `comp:CreateDynamicMaterialInstance(slot, baseMaterial, FName("None"))`
then set texture parameters (a base material is borrowed from a game asset and retextured).

## Loading assets

- Game assets by full path with `StaticFindObject` / `LoadAsset` (`gameAsset(path)`).
- Pak assets: `AssetRegistryHelpers:GetAsset({PackageName=FName(dir.."/"..name), PackagePath=FName(dir), AssetName=FName(name)})`.
  Pak folders under `/Game/Mods/<PakName>` (for example `/Game/Mods/SkillPetsB`).
- Paks ship in `Content/Paks/~mods/SkillPets/` as `SkillPets_P`, `SkillPetsB_P`, `SkillPetsC_P`, `SkillPetsR_P`
  (`.pak`, `.ucas`, `.utoc` each).

## Moving the pet

- Ground: `KismetSystemLibrary:LineTraceSingle(pawn, start, end, 0, false, {}, 0, out, true, col, col, 0)` straight
  down from `refZ + 220` to `refZ - 500`; read `out.OutHit.ImpactPoint.Z`.
- Obstacles: short traces in four directions push the position away by 30 units per blocked side (`clearOf`).
- Place: `a:K2_SetActorLocationAndRotation(loc, rot, false, out, true)`; if the engine refuses it, fall back to
  `K2_SetActorLocation` and stop rotating. Floaters add `hover + 12% * sin(t * 2.2)`.
- Animation: `mesh:PlayAnimation(anim, true)` with walk vs idle chosen by movement.
- Collision for interaction box: `box:SetCollisionProfileName(FName("TraceOnlyWorldActor"), true)`.

## The registry leak and RegSweep

Every call with an out-param table leaks a Lua registry reference in the audited UE4SS build. `LineTraceSingle` and
`K2_SetActorLocation*` are called continuously, so every table passed as an out param is wrapped in `REGSWEEP.mark(t)`
and a sweep in the main loop clears them (see [guides/execution-model.md](../guides/execution-model.md)).

## Interaction prompt

The game's E prompt comes from an invisible carrier: `BP_InteractablePlayerTeleporter` stripped bare. The mod hooks
`PlayerInteractionManager:Multicast_AcknowledgeInteractionRequest`, which only compares the interacted object's name
and sets a flag. If the carrier is unavailable it listens for the pet key itself and draws its own prompt line.
Conversation: `ConversationParticipantComponent:ServerAdvanceConversation` sets an `advanced` flag while a dialogue is
open.

## Skill and XP detection

Reads XP totals of each skill once a second (the XP-gain hook misses native XP). A chance roll per XP point, certain
at a per-skill threshold. Mining's pet is Pet Rock (that mod folded in). Pet Rock coexistence uses shared variable
`PetRock.State`.

## Extension hooks

`looks.lua` and `behaviors.lua` return tables with `onSpawn`, `onTick`, `onIdle`, `onEvent`, each called in `pcall`;
a missing file is skipped. Good pattern for optional per-feature scripts.

## Reusable recipes

| Need | Take this |
|---|---|
| Local-only actor | deferred spawn, `bSkipSpudStore`, no replication concern since never networked |
| Pre-spawn configuration | `BeginDeferredActorSpawnFromClass` then `FinishSpawningActor` |
| Walk on terrain | down trace + obstacle push |
| Own mesh with no skeleton of our own | skinned mesh + `SetLeaderPoseComponent` on a game creature |
| Ship models | pak under `Content/Paks/~mods/<Name>` + `AssetRegistryHelpers:GetAsset` |
| Many out-param calls per frame | RegSweep |

## Cautions

- Pets exist on the owner's client only. Other players do not see them.
- Pak assets are authored in the author's own Unreal project; we have no pipeline for that yet.
