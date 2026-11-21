# Guide: spawning, moving and cleaning up actors and effects

**Use this when** your mod puts something in the world: a prop, a creature, a pet, a rock, a marker, a light, an effect.

## Spawn

Simple:

```lua
local actor = world:SpawnActor(class, {X=x,Y=y,Z=z}, {Pitch=0,Yaw=yaw,Roll=0})
```

Deferred (configure before construction scripts run, SkillPets):

```lua
local gs  = StaticFindObject("/Script/Engine.Default__GameplayStatics")
local raw = gs:BeginDeferredActorSpawnFromClass(pawn, cls, xf, 2, nil, 0)   -- 2 = always spawn; xf = FTransform table
local a   = raw:get() or raw
a.bSkipSpudStore = true                    -- never written into the world save
-- set mobility, meshes, properties here
gs:FinishSpawningActor(a, xf, 0)
```

- `world` from `UEHelpers.GetWorld()` or `pc:GetWorld()`.
- **`bSkipSpudStore = true`** keeps the actor out of the world save. Then your mod must recreate it on load.
- **The game removes actors spawned where the world has not loaded.** Starfall: a rock placed 163 m from the player vanished after 8 s. Only spawn near the player and keep it alive only while a player is close.
- **Local-only actors are visible only on your machine.** A map icon on a local actor shows only on your map (Starfall). Spawned pets are not seen by other players (SkillPets).
- Classes used: `/Script/Engine.StaticMeshActor`, `SkeletalMeshActor`, `TargetPoint` (position only), `Actor`, `PointLight`, game Blueprints such as `BP_BaseInteractableNPC_C` and `DivineRock` types.

## Tag everything you own and clean up by tag

```lua
local tags = actor.Tags; tags[#tags+1] = FName("MyMod")
-- cleanup after a reload or crash:
for _, cls in ipairs(OWNED_CLASSES) do
  for _, a in ipairs(FindAllOf(cls) or {}) do
    if valid(a) and a:ActorHasTag(FName("MyMod")) then a:K2_DestroyActor() end
  end
end
```

Keep an explicit list of owned classes so the sweep is bounded. Compare actors with `GetAddress()`.

## Reuse a game actor for new behaviour (Starfall)

Spawning the game's own Divine Rock as a "star" gave mining, pickaxe gating, drops, XP and the break burst for free. The mod only:
1. spawned it; `bSkipSpudStore = true`; `SetActorScale3D`;
2. turned off its behaviours: `actor["Hover ZScale"] = 0`, `actor.RotatingMovementComponentStable:Deactivate()`, hid its swirl `actor.NS_DivineRock_Loop:SetVisibility(false, true)` + `Deactivate()`;
3. set health: `actor.HealthComponent:ModifyMaxHealth(h)`, `:SetHealth(v, "ModName")`;
4. renamed it by hooking `GetDisplayName` and returning `FText` for its own address only;
5. watched it by polling `HealthComponent:GetAuthoritativeHealth()`, `actor:GetState()` and `GetDestroyReason()`.

## Local-only bodies (SkillPets)

| Kind | Build |
|---|---|
| Static prop | `StaticMeshActor`; `c:SetMobility(2)`, `SetCollisionProfileName(FName("NoCollision"), true)`, `SetCollisionEnabled(0)`, `SetCanEverAffectNavigation(false)`, `SetStaticMesh(mesh)` |
| Game NPC | spawn the NPC class; set `DisplayName`; destroy its `InteractionComponent`s; `SetCollisionEnabled(0)` on every `PrimitiveComponent`; animate via `a.Mesh` |
| Skeletal | `SkeletalMeshActor`; try `SetSkeletalMeshAsset(mesh)`, then `SetSkinnedAssetAndUpdate(mesh, true)`, then `SetSkeletalMesh(mesh, true)`; destroy on failure |
| Own model on a game rig | add a second `SkeletalMeshComponent`, `SetSkeletalMeshAsset(ownMesh)`, `fc:SetLeaderPoseComponent(gameCreatureComponent, true, false)`, hide the leader (`SetHiddenInGame(true,false)` or `SetRenderInMainPass(false)` + `SetRenderInDepthPass(false)` + `SetCastShadow(false)`); `VisibilityBasedAnimTickOption = 0` keeps it animating hidden |

The leader has **no anim instance**; reading through it crashed. Fallback chain: if a creature route fails, mark the route failed for the session and use the static prop, so something always shows.

Other calls: `a:SetActorScale3D({X,Y,Z})`, `comp:K2_AttachToComponent(parent, FName(bone), 1, 1, 1, false)`, `comp:CreateDynamicMaterialInstance(slot, base, FName("None"))`, `mesh:PlayAnimation(anim, true)`.

## Move and place

```lua
a:K2_SetActorLocationAndRotation(loc, rot, false, {}, true)     -- if refused, fall back to K2_SetActorLocation(loc, false, {}, true)
```

**Ground height:**

```lua
local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
local out = {}
local hit = ksl:LineTraceSingle(pawn, {X=x,Y=y,Z=refZ+220}, {X=x,Y=y,Z=refZ-500}, 0, false, {}, 0, out, true, col, col, 0)
local z = (out.OutHit or out).ImpactPoint.Z
```

Obstacle push: four short horizontal traces; for each blocked side move 30 units the other way. **Each out-table call leaks a registry reference** on this build, so a per-frame trace must use the sweep ([performance](performance.md)).

Floaters: `Z + hover + 12% * sin(t * 2.2)` for a slow bob. Grab-and-carry (RSDWTools): one self-terminating loop, destination and rotation tables allocated once and mutated in place, camera view from `pc:GetPlayerViewPoint`.

## Effects, sound, lights

- Niagara: `NiagaraFunctionLibrary:SpawnSystemAtLocation(world, system, vec, rot, ...)` (Starfall `fx.lua`).
- Camera shakes reused from `/Game/Gameplay/AI/DragonVelgar/` (`BP_Dragon_Landing_CameraShake`).
- A `PointLight` actor with `K2_SetActorLocation` for glows.
- Hide a game actor's effect without removing it: `comp:SetVisibility(false, true)` then `Deactivate()`.

## Assets

- Game assets by full path: `StaticFindObject(path)`, else `LoadAsset(path)` then retry; for a Blueprint class strip `_C`, `LoadAsset(package)`, look again.
- **Slots with fallbacks:** `Assets.slots[name] = { candidate1, candidate2 }`; `resolve(slot)` returns the first that loads, caches it and logs which; `check()` at startup reports empty slots so a game patch that moves an asset is one log line (Starfall).
- Pak assets: `AssetRegistryHelpers:GetAsset({PackageName=FName(dir.."/"..name), PackagePath=FName(dir), AssetName=FName(name)})`; see [native-and-paks](native-and-paks.md).
- Do not load assets before the world has settled.

## Pitfalls

- Spawning far from the player (the game removes it).
- Forgetting to tag (cannot clean up after reload).
- Reading anim instances on leader-posed meshes.
- Per-frame traces without a sweep.
- Expecting other players to see local actors.

## Seen in

[sources/Starfall.md](../sources/Starfall.md), [sources/SkillPets.md](../sources/SkillPets.md), [sources/ResourceAtlas-and-PenguinFinder.md](../sources/ResourceAtlas-and-PenguinFinder.md), [sources/RSDWTools.md](../sources/RSDWTools.md).
