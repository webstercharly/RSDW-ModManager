# Guide: native code, paks and asset loading

**Use this when** a mod needs more than Lua: its own models and textures, Blueprint logic, or native hooks.

## Pak mods (own content)

- Layout shipped in a zip: `Content/Paks/~mods/<Name>/<Name>_P.pak`, `.ucas`, `.utoc` (an IoStore triple per pak). SkillPets ships four (`SkillPets_P`, `B`, `C`, `R`); RuneSchema plugins ship `Networking_P`, `RegistryBridge_P`, `RuneSchemaQuestItems_P`.
- Game-root paths in the zip if you ship both Lua and paks: `RSDragonwilds/Binaries/Win64/ue4ss/Mods/<Name>/...` and `RSDragonwilds/Content/Paks/~mods/<Name>/...`. Say so in the README.
- Content lives under `/Game/Mods/<PakName>` in the asset registry.
- Load from Lua:

```lua
local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local asset = arh:GetAsset({ PackageName = FName(dir.."/"..name), PackagePath = FName(dir), AssetName = FName(name) })
if asset:IsValid() then ... end                -- a missing pak means nil, so fall back to a game asset
```

- Always have a fallback when the pak is missing (SkillPets falls back to a static prop).
- We have **no pipeline for authoring paks** yet; the authors build them in an Unreal project.

## Blueprint "ModActor" loader (RuneSchema)

For pak-based logic mods:

```lua
local helpers = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local class = helpers:GetAsset({ PackageName = UEHelpers.FindOrAddFName("/Game/Mods/"..name.."/ModActor"),
                                 AssetName   = UEHelpers.FindOrAddFName("ModActor_C") })
local actor = world:SpawnActor(class, {}, {});  actor.PreBeginPlay()
RegisterBeginPlayPostHook(function(ctx) ... actor.PostBeginPlay() end)     -- match class path /Game/Mods/<name>/ModActor.ModActor_C
RegisterLoadMapPostHook(function(_, world) started = {}; startWorld(world:get()) end)
```

Names are validated against `^[A-Za-z0-9_]+$`. UE4SS's bundled `BPModLoaderMod` is the standard version of this (it reads `load_order.txt`).

## Native DLLs

| Style | Example |
|---|---|
| UE4SS C++ mod `dlls/main.dll` exporting Lua globals | MiniMap, RuneSchema, RSDWTools wrapper (`BridgeLineInitCpp`, `PollRequestCpp`, `WriteAckCpp`) |
| Lua calls an export directly | `local f, err = package.loadlib(dir.."../Native/X.dll", "Export"); assert(f, err); f()` (Class Specialisations) |
| Native hooks with MinHook | Class Specialisations' ten DLLs hook game functions Lua cannot |

- **Handshake before use:** Class Specialisations' Lua writes `pending` to a status file, calls the DLL's `CheckCompatibility`, which must rewrite it to `ready`; otherwise the mod refuses to start. A global flag records success.
- Version native modules in the file name (`MagicRuntime-070.dll`).
- A native crash leaves no Lua error; read both logs.
- **None of the DLLs in `References/` or the installed mods have been audited.** Never load one from `References/`.
- For us the project rule is PC-only and no new native dependencies unless chosen.

## Loading assets from Lua

| Source | How |
|---|---|
| Already loaded | `StaticFindObject(fullPath)` |
| Game package | `LoadAsset(package)` then `StaticFindObject(package.."."..name)`; Blueprint class `..._C` |
| Pak | `AssetRegistryHelpers:GetAsset` as above |
| PNG on disk | `KismetRenderingLibrary:ImportFileAsTexture2D(contextObject, path)` ([ui-construction](ui-construction.md)) |
| Many candidates | resolve slots with fallbacks ([actors-and-world](actors-and-world.md)) |

Do not call `LoadAsset` before the world has settled. A soft reference property must not be read ([reading-writing-values](reading-writing-values.md)).

## Why native at all

The Lua-only mods in this library cover most needs. Native code appears where Lua cannot hook (native functions that are not UFunctions), needs speed, or needs to bridge a process (RSDWTools shared memory). Prefer Lua plus polling first.

## Seen in

[sources/SkillPets.md](../sources/SkillPets.md), [sources/RuneSchema-and-ModMenu.md](../sources/RuneSchema-and-ModMenu.md), [sources/ClassSpecialisations.md](../sources/ClassSpecialisations.md), [sources/RSDWTools.md](../sources/RSDWTools.md).
