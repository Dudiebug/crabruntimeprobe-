# Campaign Status

- Campaign: `crabruntimeprobe-read-map`
- Updated: 2026-05-05T20:16:13.036Z
- Current phase: none
- Next recommended phase: `local-inventory-array-shallow-read`
- Latest session: 20260505T072250Z
- Latest commit: 591389d5f71e99e2c19f7c287290cbf853a8e496
- Latest summary: evidence/runtime/20260505T072250Z/diagnostic_summary.txt

## Completed Phases

- `smoke-startup` - Startup smoke
- `executeDelay` - executeDelay tick driver
- `observe-context` - Observe runtime context
- `equipment-property-read` - Equipment data asset property reads
- `health-playerstate-read` - PlayerState health scalar reads
- `health-playerstate-watch` - Solo PlayerState health watch
- `multiplayer-roster-read` - Multiplayer roster identity read
- `multiplayer-health-playerstate-watch` - Multiplayer PlayerState health watch

## Partial Phases

- `multiplayer-resource-visibility-read` - Multiplayer resource visibility read: remote_resources_partial; Multiple PlayerState candidates were sampled and some resource fields were visible remotely, but visibility was partial.
- `local-inventory-array-shallow-read` - Local inventory array shallow read: crash_suspect_local_inventory_shape_visible; Local inventory array fields were visible as shallow userdata shapes, but crash_2026_05_05_07_24_18.dmp exists after prepare/run; keep the phase crash-suspect pending safer confirmation.

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

- None.

## Confirmed Safe Paths

- `CrabPS.WeaponDA` via `GetPropertyValue`
- `CrabPS.AbilityDA` via `GetPropertyValue`
- `CrabPS.MeleeDA` via `GetPropertyValue`
- `CrabPC -> PlayerState -> CrabPS -> HealthInfo` read-only PlayerState health path
- `CrabPC -> PlayerState` local identity reads with redacted/fingerprinted identity values
- confirmed visible multiplayer roster reads
- partial remote multiplayer PlayerState resource reads for crystals, slots, equipment, and health scalars

## Identity And Roster Notes

- Local player identity visible: yes
- Max visible player count observed: 2
- Any candidate exposed more than one player: yes
- Roster source candidates attempted: Identity.CrabGS.SourceCandidate, Identity.FindAll.PlayerStateCandidates, Identity.GameState.SourceCandidate, Identity.PlayerArray.Shape, Identity.PlayerControllerCandidates, Identity.VisiblePlayers.SourceCandidate
- Visible roster source resolved: yes
- Raw IDs/names emitted: no, redacted/fingerprinted by default
- PlayerName and UniqueId can be fingerprinted from PlayerState identity reads without emitting raw values.
- `solo-or-host` means local-player-present in the current detector; it is not proof that the run was solo and cannot distinguish true solo from multiplayer host-like local context.
- Visible player roster source is confirmed; future auto-room grouping still requires matched host and joined-client runs.

## Multiplayer Resource Visibility

- Summary: partial
- Resource visibility class: remote_resources_partial
- Player count sampled: 4
- Fields visible across more than one PlayerState: AbilityDA, BaseMaxHealth, Crystals, HealthInfo, HealthInfo.CurrentHealth, HealthInfo.CurrentMaxHealth, Keys, MaxHealthMultiplier, MeleeDA, NumAbilityModSlots, NumMeleeModSlots, NumPerkSlots, NumWeaponModSlots, WeaponDA
- Fields only visible on local PlayerState: none
- Fields returning nil/errors: AbilityMods, MeleeMods, Perks, Relics, WeaponMods
- Readable categories by candidate: crystals=4/4, slots=4/4, equipment=4/4, inventory array counts=0/4, health=4/4
- Supports future P2P resource merge design: partial
- CrabInvSync v2 implication: P2P-style merge is plausible for crystals, slots, equipment, and possibly health inputs.
- Inventory item sync still needs separate research; current shallow count-only inventory array visibility is unresolved and does not expose item metadata.
- An external relay/server may still be needed for inventory until array/item metadata visibility or another safe carrier is proven.
- Raw IDs/names emitted: no, redacted/fingerprinted by default
- No writes/RPCs/HUD hooks/deep array element reads/InventoryInfo/Enhancements are part of this phase.

## Local Inventory Array Visibility

- Summary: local_inventory_shape_visible_crash_suspect
- Local inventory array status: crash_suspect_local_inventory_shape_visible
- Local PlayerState present: yes
- Fields readable by shallow shape/count: AbilityMods, MeleeMods, Perks, Relics, WeaponMods
- Fields nil or unsupported: none
- Array value kinds: AbilityMods=userdata, MeleeMods=userdata, Perks=userdata, Relics=userdata, WeaponMods=userdata
- Array counts available: no; current helper only counts Lua tables and these values were userdata shapes
- Slot scalar values: NumAbilityModSlots=12, NumMeleeModSlots=12, NumPerkSlots=24, NumWeaponModSlots=24
- Array elements dereferenced: no
- InventoryInfo and Enhancements were not read; writes/RPCs/HUD hooks/deep arrays were disabled.
- A crash dump exists after this run, so this path remains crash-suspect pending another safer confirmation pass.
- Remote inventory array visibility remains unresolved separately.

## Confirmed Unsafe Paths

- HUD ReceiveDrawHUD tick hook remains blocked by default.
- `FindFirstOf.CrabHC` is not confirmed as a player-health source; imported evidence has seen an unscoped destructible/barrel candidate.
- Writes and RPCs are disabled and are outside this campaign version.

## Untested Paths

- Vanilla multiplayer local PlayerState health visibility is confirmed only after `multiplayer-health-playerstate-watch` evidence exists; pooled/shared health is a CrabInvSync design concept, not vanilla RuntimeProbe evidence.
- Multiplayer roster identity is only complete after visible roster evidence exists; local PlayerState identity alone is partial evidence.
- Roster candidate probes currently include GameState/GameStateBase source identity, CrabGS source identity, PlayerArray shape, capped FindAll PlayerState-like candidates, capped PlayerController/CrabPC candidates, and a capped visible players source candidate.
- Crystals, slots, equipment, and inventory array counts are only covered by `multiplayer-resource-visibility-read` after imported resource visibility evidence exists.
- Local inventory array visibility is separate from remote PlayerState resource visibility and is covered only by `local-inventory-array-shallow-read` after imported evidence exists.
- `InventoryInfo` and enhancements remain placeholders until explicit probe sets are implemented.
- Deep arrays and InventoryInfo gates remain off until their explicit reviewed phases.

## Safety Gate Summary

- Default config remains `tickDriver = none`, `probeSet = shallow-core`, and all research gates false.
- Campaign read phases never enable writes, RPCs, or HUD hooks.
- `allowHealthProbes` is enabled only for explicit health phases and `multiplayer-resource-visibility-read` health scalar checks.
- `allowIdentityProbes` is enabled only for the explicit multiplayer roster and resource visibility phases; `allowRawIdentityEvidence` remains false by default.
- `allowResourceVisibilityProbes` is enabled only for `multiplayer-resource-visibility-read`.
- `allowInventoryArrayShallowProbes` is enabled only for `local-inventory-array-shallow-read`.
- `allowDeepArrayProbes` and `allowInventoryInfoProbes` are not enabled by implemented phases.
