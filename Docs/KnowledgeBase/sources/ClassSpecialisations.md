# Class Specialisations & Armour Rolls 0.9.6 (solo): implementation notes

Source: `References/OnlineMods/ClassSpecialisations-ArmourRolls/0.9.6-solo/extracted/Class Specialisations & Armour Rolls - SOLO ONLY/`
(about 85 Lua files, 10 native DLLs in `Native/`, settings in `Data/`). No licence for the Lua; `MinHook-LICENSE.txt` and
`UE4SS-LICENSE.txt` are included for the DLLs. **Survey level only:** the Lua is written in a compact style (many statements per
line), and the native DLLs are binaries we have not audited, so this note records the visible structure, not the game logic.

## Entry and native bridge

`Scripts/main.lua` is four lines: resolve own directory, run `compatibility.lua`'s `check()`, load `settings-editor.lua`, and return
`fixed-runtime.lua`'s `new()`.

Native code is called **from Lua with `package.loadlib`**:

```lua
local check, err = package.loadlib(dir..'../Native/ClassCompatibility.dll', 'CheckCompatibility')
assert(check, err); check()
```

- A compatibility handshake: Lua writes `pending` to `Data/compatibility-status.txt`, calls the DLL export, which must overwrite it
  with `ready`; anything else makes the mod refuse to start (`assert(result=='ready', ...)`). A global flag
  (`ClassNativeCompatible092`) records success, so the check runs once per Lua state.
- Other exports seen: `ModSettings.dll` `MeasureHudLayout`. The native layer uses MinHook to hook game functions that cannot be hooked
  from Lua. Native modules are versioned in file names (`ArmourRolls-001`, `BowRuntime-080`, `MagicRuntime-070`, `SpellHit-080`,
  `TalentRuntime-080`, `PatientHunter-052`, `GeneratedDamage-075`, `EffectHandles`).

## Settings and data files

- Plain text `key=value` with strict validation. Example `hud-layout.lua`: reads at most 64 KB (reads 65,537 bytes and rejects if over),
  parses `^([%w_]+)=([%d%.]+),([%d%.]+)$`, requires x and y in 0..1, rejects duplicate keys, and only accepts keys matching
  `^defence_%a+$` or `^%a+_%d+$`. Returns nil for any bad line so a corrupt file is discarded whole.
- `Data/fixed-tuning.txt` is tuning numbers per talent, named `<class>_<level>_<field>` (for example `guardian_10_health=30`).
- Schemas ship as `armour-rolls-schema.txt`, `fixed-settings-schema.txt`.

## Observed module families (from file names)

`class-*.lua` class rules (armour, body, capacity, crouch, fields, rewards, spells, timing), `fixed-*.lua` fixed-tuning runtime
(blocks, bow timing, buildup, catalogue, controller, defense, layout, policy, ranged, runes, spells, status, storage),
`armour-roll-*.lua` (catalogue, crafting, policy, ranged, runtime, store, tooltip), `talent-ui*.lua`, `menu-*.lua` (hotkeys, input,
intent, navigation), `hud*.lua` / `defence-hud.lua` / `status-medallion.lua`, `native-*.lua` (presentation, skin) and `*-native.lua`
bridges, `damage-buffer.lua`, `melee-weapon.lua`, `combat-target.lua`, `overlap-actors.lua`, `reaction-guard.lua`, `snare.lua`,
`wind.lua`, `effects.lua`, `enchant.lua`, `storage.lua`, `legacy.lua`.

## Patterns visible in the source samples

- **Candidate sets keyed by address:** `x.sense.candidates[o:GetAddress()] = o` from `NotifyOnNewObject`, so each object is stored once.
  Used for `HuntersSenseEffectInstance`, `TempestShieldGameplayEffectInstance`, `PlayerVitalsWidget`, `ReticleWidgetBase`,
  `DominionSpellActor`, `GroundedExplodingProjectile`, `CraftingMenuBase`, `CraftingUIAPI`, `InventorySlotBase`, `TopBarMenu_InGame`.
- **Self-unregistering observers:** the callback returns `true` once `M.stopped` (or `not self.active`), which removes the notification.
- **Registered hooks tracked for teardown:** `M.hooks[#M.hooks+1] = {path, RegisterHook(path, before, after)}` keeps the pre/post ids
  that `RegisterHook` returns, so the mod can later call `UnregisterHook(path, preId, postId)`. Several patterns use `pcall(RegisterHook, ...)`
  and a `type(RegisterHook)=='function'` guard.
- **Key binds** via `RegisterKeyBind(Key[name], fn)` pushing to an `input` queue (`Key.Q` / `Key.E` push -1 / +1 for menu navigation).
- **UI art from game assets:** `/Game/Art/UI/Skills/T_Skill_IconHolder`, `T_Skills_Radial_Centre`, `T_Skills_Diamond`, `T_Skills_Card_Highlight`,
  `T_Skills_Trim`, `T_Skills_XP_Menu_Bg`, `T_Skills_Divider`, `T_SkillList_Full_Screen`, `T_Skills_Surround`, `T_Skills_Border_Highlights`; icons
  `Icons/T_Notification_Skill_Attack`, `_Magic`, `_Ranged`, `2025/Skill_Chargers/T_Icon_Surge`. Colours stored as linear tables
  (gold `{0.5841, 0.4020, 0.1590}`, ivory, muted, panel `{0.022, 0.016, 0.011, 0.94}`), a ready palette that matches the game's skills screen.

## Why it is useful to us

- Shows **Lua plus native DLL** design: a native handshake, a hook layer in C++, a data layer in text files.
- A model for **strict, bounded config parsing** (size cap, key whitelist, all-or-nothing).
- The **list of skills-screen texture paths** and a palette matched to the game UI.

## Cautions

- Mixed licensing and unaudited binaries. Do not load `Native/*.dll` from `References/`.
- Naming conventions suggest it is built against game version 1.0 hooks that the DLLs rely on; compatibility checks gate startup.
