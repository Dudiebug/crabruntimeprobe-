# CrabModFramework Roadmap

`docs/` is the source of truth for this plan. Wiki output may exist when generated automatically by the existing docs pipeline, but no separate wiki workflow is planned.

## RuntimeProbe Evidence Tracks

DataAsset catalog track:

- `perk-da-catalog-read`: implemented read-only phase for safely discoverable perk DataAssets.
- `weaponmod-da-catalog-read`: placeholder.
- `abilitymod-da-catalog-read`: placeholder.
- `meleemod-da-catalog-read`: placeholder.
- `weapon-da-catalog-read`: placeholder.
- `ability-da-catalog-read`: placeholder.
- `melee-da-catalog-read`: placeholder.

Passive event/function watcher track:

- `event-watch-smoke`: placeholder.
- `event-watch-equipment`: placeholder.
- `event-watch-crystals`: placeholder.
- `event-watch-slots`: placeholder.
- `event-watch-pickups`: placeholder.
- `event-watch-inventory-replication`: placeholder.

Remaining inventory research track:

- `inventory-array-shallow-read`: unresolved.
- `inventory-array-count-read`: unresolved.
- `inventory-element-da-read`: unresolved.
- `inventoryinfo-scalar-read`: blocked pending safety review.
- `enhancements-read`: blocked pending safety review.

## Framework Track

- `framework-skeleton`: create the UE4SS-loaded CrabModFramework package shape.
- `safe-context-api`: expose context, role, lifecycle, and gate state.
- `safe-playerstate-api`: expose proven-safe CrabPS read paths.
- `safe-dataasset-catalog-api`: expose catalog evidence through typed read-only definitions.
- `safe-property-read-wrappers`: classify read/nil/error/unsupported outcomes consistently.
- `safe-event-watcher-wrappers`: passive wrappers for naturally-called events.
- `capability-declarations`: require mods to declare safe and experimental capabilities.
- `direct-ue4ss-call-linting`: flag unsafe raw UE4SS calls outside wrappers.
- `experimental-write-api`: future-only framework work, never a RuntimeProbe phase.

## Current Evidence Baseline

`safe-scalar-watch` works and collected 119 samples in a normal play session. It safely observed changes to `WeaponDA`, `AbilityDA`, `MeleeDA`, `Crystals`, `CurrentHealth`, `CurrentMaxHealth`, `BaseMaxHealth`, and `Num*Slots`.

`Num*Slots` changed from startup/run defaults to effective in-run values. The locked/max/total slot model remains conservatively unresolved.

No writes, RPCs, HUD hook, deep arrays, inventory traversal, InventoryInfo, or Enhancements were used. Crash suspicion was none.
