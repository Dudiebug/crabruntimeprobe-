# CrabModFramework Roadmap

`docs/` is the source of truth for this plan. Wiki output may exist when generated automatically by the existing docs pipeline, but no separate wiki workflow is planned.

## RuntimeProbe Evidence Tracks

Direct long-play recorder:

- `max-safe-play-recorder`: implemented direct profile for up to 60 minutes of normal play. It combines all currently proven-safe scalar state recording with capped perk DataAsset catalog snapshots. It is not a campaign replacement and does not authorize writes, live inventory internals, InventoryInfo, Enhancements, deep arrays, RPCs, HUD hooks, or arbitrary UObject crawling.

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

Future layers that may graduate into `max-safe-play-recorder` only after dedicated campaign proof:

- `inventory-array-count-read`.
- `inventory-element-da-read`.
- `inventoryinfo-scalar-read`.
- `enhancements-read`.
- `event-watch-smoke`.
- `event-watch-equipment`.
- `event-watch-crystals`.
- `event-watch-slots`.
- `event-watch-pickups`.
- `event-watch-inventory-replication`.
- `weaponmod-da-catalog-read`.
- `abilitymod-da-catalog-read`.
- `meleemod-da-catalog-read`.
- `weapon-da-catalog-read`.
- `ability-da-catalog-read`.
- `melee-da-catalog-read`.

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

A later `safe-scalar-watch` collect produced only `Debug.StartupSmoke` and `Debug.WriterSelfTest`, did not run `SafeWatch.Scalar.Sample`, collected zero PlayerState-present samples, and ended failed. Treat that session as failed/no-sample diagnostic evidence only, not useful confirmed evidence.
