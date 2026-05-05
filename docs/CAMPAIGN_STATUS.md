# Campaign Status

- Campaign: `crabruntimeprobe-read-map`
- Updated: 2026-05-05T03:17:51.912Z
- Current phase: none
- Next recommended phase: `observe-context`
- Latest session: 20260505T025430Z
- Latest commit: 55820ce4522abef78d690789ab1524ff6668bfe0
- Latest summary: evidence/runtime/20260505T025430Z/diagnostic_summary.txt

## Completed Phases

- `smoke-startup` - Startup smoke
- `executeDelay` - executeDelay tick driver
- `equipment-property-read` - Equipment data asset property reads
- `health-playerstate-read` - PlayerState health scalar reads
- `health-playerstate-watch` - Solo PlayerState health watch

## Failed Phases

- None.

## Blocked Phases

- `crystals-read` - Crystals read placeholder: Probe set is not implemented yet.
- `slots-read` - Slots read placeholder: Probe set is not implemented yet.
- `inventory-array-shallow-read` - Inventory array shallow read placeholder: Probe set is not implemented yet.
- `inventory-array-count-read` - Inventory array count read placeholder: Probe set is not implemented yet.
- `inventory-element-da-read` - Inventory element data asset read placeholder: Probe set is not implemented yet and would require explicit deep-read review.
- `inventoryinfo-scalar-read` - InventoryInfo scalar read placeholder: Probe set is not implemented yet and InventoryInfo remains disabled until this explicit phase.
- `enhancements-read` - Enhancements read placeholder: Probe set is not implemented yet.

## Pending Phases

- `observe-context` - Observe runtime context
- `multiplayer-health-playerstate-watch` - Multiplayer PlayerState health watch

## Confirmed Safe Paths

- `CrabPS.WeaponDA` via `GetPropertyValue`
- `CrabPS.AbilityDA` via `GetPropertyValue`
- `CrabPS.MeleeDA` via `GetPropertyValue`
- `CrabPC -> PlayerState -> CrabPS -> HealthInfo` read-only PlayerState health path

## Confirmed Unsafe Paths

- HUD ReceiveDrawHUD tick hook remains blocked by default.
- `FindFirstOf.CrabHC` is not confirmed as a player-health source; imported evidence has seen an unscoped destructible/barrel candidate.
- Writes and RPCs are disabled and are outside this campaign version.

## Untested Paths

- Multiplayer health scaling remains unproven until `multiplayer-health-playerstate-watch` evidence exists.
- Crystals, slots, inventory arrays, `InventoryInfo`, and enhancements are placeholders until explicit probe sets are implemented.
- Deep arrays and InventoryInfo gates remain off until their explicit reviewed phases.

## Safety Gate Summary

- Default config remains `tickDriver = none`, `probeSet = shallow-core`, and all research gates false.
- Campaign read phases never enable writes, RPCs, or HUD hooks.
- `allowHealthProbes` is enabled only for explicit health phases.
- `allowDeepArrayProbes` and `allowInventoryInfoProbes` are not enabled by implemented phases.
