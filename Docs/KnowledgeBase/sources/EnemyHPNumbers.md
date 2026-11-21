# EnemyHPNumbers 1.3.2: implementation guide

Source: `ue4ss/Mods/EnemyHPNumbers/Scripts/main.lua` (1,594 lines), read in place (it is installed, not in `References/`).
Author Maxxfilth (same author as Slayer, MapMarkers, AutoTool). No licence file: learn, do not copy.

**What it does:** shows exact health on enemy and boss bars ("24 / 30"), weakness icons, and numbers on your own stamina and special
attack bars. Read-only towards the game.

**Why read it:** the clearest example of **finding which game values are real**, **reusing a game widget instead of building one**, and
**tracking pooled widgets safely**.

## The most useful finding: dead mirrors

`HealthComponent.AuthoritativeHealth` and `.MaxHealth` **never change** when an enemy is damaged (30.0 stays 30.0 after 6 damage;
`MaxHealth` reads 0.0). A mod built on them shows full health forever and looks right in a short test. Two live routes agree exactly:

```lua
-- exact values
lib = StaticFindObject("/Script/Dominion.Default__AttributeFunctionLibrary")
hp  = StaticFindObject("/Script/Dominion.HealthAttribute");  max = StaticFindObject("/Script/Dominion.MaxHealthAttribute")
lib:BP_TryGetFloatAttributeValue(char, hp, -1.0, outA, outB)     -- reads outA.OutAttributeValue, outA.OutbFound
-- the drawn fraction (cannot be wrong, it is what is on screen)
widget.VitalFillValue                                            -- 0..1;  VitalBarValue is NOT the fill (reads 0.1 at full)
```

**UE4SS out-parameter quirk (measured):** *all* out params land in the **first** out table, with the `V.` prefix visible in logs, not one
table each. Reading `OutbFound` from the second table always gives nil. The code accepts either layout:
`found = outA.OutbFound; if found == nil then found = outB.OutbFound end`. Passing an empty table per out param is the call convention.

## Finding enemies (`scanEnemies`)

- `FindAllOf("AiHealthBarComponent")` costs about 47 ms on the game thread, so it runs on a long interval (`ScanSeconds`, minimum 2 s).
- Per component: `comp.AICharacter` (the enemy), `comp.HealthComponent`; key = the character's full name; skip `Default__`.
- Distance from the player via `K2_GetActorLocation`; capped by `MaxDistance` (40 m) and `MaxTracked` (25).
- Records refresh each scan (`rec.char`, `rec.comp`): "the component can be rebuilt while the actor lives". Records not seen are `drop`ped.
- Boss components (class name contains `Boss`) are only tracked to know a boss is near.

## Per-tick cost control (`updateOne`)

1. Re-validate **every handle before every use**; if invalid, `drop(key)`.
2. Cheap change detector: one float read, `w.VitalFillValue`.
3. Only if the fill moved (by more than 0.0005), pay for attribute calls. Max is read once and refreshed about every 20 updates.
4. **Death:** `VitalFillValue` *freezes* at its last value when an enemy dies (a killed Kebbit still read 0.6), so a stopped fill cannot signal death.
   Re-verify against the attribute about once a second (`rec.verify` counter 4); `cur == nil or cur <= 0` means dead, so `drop`.
5. Text is only rewritten if it differs from `rec.shown`.
6. Decorations (icons) are re-applied only when a setting or species data changes, at most `DECO.budget` bars per tick.

## Drawing by reusing a game widget

`WBP_AI_Healthbar_C` ships with an unused `TextBlock` named `DebugHealthValues` (placeholder `'DebugHealth'`, collapsed).

```lua
dbg = w.DebugHealthValues
dbg:SetText(FText("24 / 30"));  dbg:SetVisibility(4)        -- 4 = SelfHitTestInvisible
```

The numbers then inherit the bar's position, scale, facing and distance rules. `ValueText` is **not** valid on that widget.

**Restore discipline:** the original text and visibility are captured once per *widget* in `TOUCHED[fullName]` before the first write
(`touch(w, key)`), and written back when tracking stops. Reason: **these widgets are pooled**, so a stale number would otherwise ride along to
whichever enemy borrows the widget next. A sweep (`sweepTouched`) catches widgets whose enemies vanished.

**Boss bars:** a boss does not use a world bar. `BP_BossAiHealthBarComponent_C:GetUserWidgetObject()` is invalid; the bar is HUD widget
`WBP_AI_Boss_Healthbar_C`, created on engagement, with no `DebugHealthValues`, so the mod **adds its own `TextBlock`** to the bar's overlay. It
finds the widget through the HUD subsystem (`FindFirstOf`, cached; `HUDBarsAPI` properties), retried with back-off (every `ScanSeconds`, then every 30 s
after 5 misses), at any distance.

**Player bars:** `FindAllOf("PlayerVitalsWidget")` once (retry every 5 s). For each bar field, add a TextBlock to `bar.WidgetTree.RootWidget:GetChildAt(1)`
(must be an `Overlay`; otherwise log once and skip), `AddChildToOverlay`, centre it with `slot:SetHorizontalAlignment(2); SetVerticalAlignment(2)`,
`tb:SetJustification(1)`, `tb:SetVisibility(4)`, and copy font and colour from the game's own health number
(`w.HealthBar.ValueText.Font` / `.ColorAndOpacity`). `resetBar` removes it with `RemoveFromParent`.

## Weaknesses

- `AIAttributesComponent.DamageTypeAffinities` is a `Map<GameplayTag, EDamageTypeAffinity>`; iterate with
  `map:ForEach(function(k, v) tag = k:get().TagName:ToString(); val = v:get() end)`.
- Enum values: 0 weak, 1 resist, 2 immune. Tag depth: `DamageType.Magical` is a whole class (depth 2); `DamageType.Magical.Fire` is one type (depth 3).
- The per-type float attributes (`DamageTypeSlashMultiplierAttribute` etc.) **cannot tell weak from resist** (all read 0.25); only the map can.
- **Affinities are per Blueprint class**, so they are cached per class key (`char:GetClass():GetFullName()`), resolved once for the session, in **one
  `FindAllOf` after the loop** for all new species (never inside it).
- The internal tag `DamageType.DragonWorldEvent` is not a player-dealable type; never shown.
- Icons: untinted game icons on a coloured plate (green weak, red resists, dark immune), laid in a row under the bar. The game's own immunity
  diamonds are un-hidden when an enemy is immune to a whole class.
- Layout lesson: the health text block is centred as a whole, so a long second line widens it and the level badge lands on top of the number. Abbreviate
  names (`Magical -> Mag`).

## Shared variables published

v1.3.1 publishes what it shows as `EnemyHPNumbers.*` shared variables so an "Examine" mod can skip duplicate lines. Pattern: `ModRef:SetSharedVariable`.

## Config and keys

`cfg` table with defaults, `config.txt` overrides, Mod Menu (`mmGet`/`mmPoll`) applies live, `sanitise()` clamps. Optional `ToggleKey`: **polled** with
`engineKeyName()` + `pollKeys()` like FishingSliders (no `RegisterKeyBind`), and `drainKeys()` handles a queue.

## Reusable recipes

| Need | Take this |
|---|---|
| Real health of any AI character | `AttributeFunctionLibrary:BP_TryGetFloatAttributeValue` with `HealthAttribute`/`MaxHealthAttribute` |
| Show data on a game bar with no new widget | write to an existing unused TextBlock, capture and restore original text and visibility |
| Add text to a game widget | construct a `TextBlock`, `AddChildToOverlay`, copy font and colour from a sibling |
| Per-class data cached once | key by `GetClass():GetFullName()` |
| Cheap per-tick change detector | one drawn-value float read gating expensive calls |
| Detect death with a frozen widget value | periodic re-verify against the real attribute |
| Iterate a TMap | `map:ForEach(function(k, v) k:get() v:get() end)` |

## Cautions

- Measured 2026-09-20 to 2026-09-24 on the author's build.
- Pooled widgets are the main risk: always restore before dropping the handle.
