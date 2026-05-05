# Campaign Status

- Campaign: `crabruntimeprobe-read-map`
- Updated: 2026-05-05T04:14:01.207Z
- Current phase: `multiplayer-roster-read`
- Next recommended phase: `multiplayer-roster-read`
- Latest session: 20260505T035239Z
- Latest commit: 7b9c773f133d5464a1f5d6046bdf4ebdd565c75f
- Latest summary: evidence/runtime/20260505T035239Z/diagnostic_summary.txt

## Completed Phases

- `smoke-startup` - Startup smoke
- `executeDelay` - executeDelay tick driver
- `observe-context` - Observe runtime context
- `equipment-property-read` - Equipment data asset property reads
- `health-playerstate-read` - PlayerState health scalar reads
- `health-playerstate-watch` - Solo PlayerState health watch

## Partial Phases

- `multiplayer-roster-read` - Multiplayer roster identity read: local_identity_confirmed; Local PlayerState identity read confirmed; visible roster source remains unresolved.

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

- `multiplayer-health-playerstate-watch` - Multiplayer PlayerState health watch

## Confirmed Safe Paths

- `CrabPS.WeaponDA` via `GetPropertyValue`
- `CrabPS.AbilityDA` via `GetPropertyValue`
- `CrabPS.MeleeDA` via `GetPropertyValue`
- `CrabPC -> PlayerState -> CrabPS -> HealthInfo` read-only PlayerState health path
- `CrabPC -> PlayerState` local identity reads with redacted/fingerprinted identity values

## Identity And Roster Notes

- Local player identity visible: yes
- Max visible player count observed: 1
- Visible roster source resolved: no
- Raw IDs/names emitted: no, redacted/fingerprinted by default
- PlayerName and UniqueId can be fingerprinted from PlayerState identity reads without emitting raw values.
- `solo-or-host` means local-player-present in the current detector; it is not proof that the run was solo and cannot distinguish true solo from multiplayer host-like local context.
- `GameStateBase.PlayerArray` returned nil / was not exposed as a Lua table in the latest roster evidence.
- Visible player roster remains unresolved, so future auto-room grouping is not ready.

## Confirmed Unsafe Paths

- HUD ReceiveDrawHUD tick hook remains blocked by default.
- `FindFirstOf.CrabHC` is not confirmed as a player-health source; imported evidence has seen an unscoped destructible/barrel candidate.
- Writes and RPCs are disabled and are outside this campaign version.

## Untested Paths

- Multiplayer health scaling remains unproven until `multiplayer-health-playerstate-watch` evidence exists.
- Multiplayer roster identity is only complete after visible roster evidence exists; local PlayerState identity alone is partial evidence.
- Crystals, slots, inventory arrays, `InventoryInfo`, and enhancements are placeholders until explicit probe sets are implemented.
- Deep arrays and InventoryInfo gates remain off until their explicit reviewed phases.

## Safety Gate Summary

- Default config remains `tickDriver = none`, `probeSet = shallow-core`, and all research gates false.
- Campaign read phases never enable writes, RPCs, or HUD hooks.
- `allowHealthProbes` is enabled only for explicit health phases.
- `allowIdentityProbes` is enabled only for the explicit multiplayer roster phase; `allowRawIdentityEvidence` remains false by default.
- `allowDeepArrayProbes` and `allowInventoryInfoProbes` are not enabled by implemented phases.
