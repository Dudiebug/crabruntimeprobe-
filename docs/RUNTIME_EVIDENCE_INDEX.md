# Runtime Evidence Index

Generated from imported runtime evidence under `evidence/runtime/`.

- Access evidence files: 9
- Probe result files: 9
- Diagnostic summaries: 8
- Evidence rows: 292
- Health playerstate watch samples: 200
- Identity/roster samples: 15
- Resource visibility samples: 0
- Objectdump symbols discovered: 0

- Probe candidates doc present: yes

Objectdump discovery means a symbol exists in static dump data. It does not mean runtime access is safe.

## Health Source Scope Notes

- `CrabPS` health rows are player-state-scoped because the probe path starts from `CrabPC -> PlayerState -> CrabPS`.
- `CrabPC -> PlayerState -> CrabPS -> HealthInfo` is the only currently confirmed safe player health read path.
- `FindFirstOf.CrabHC` is unscoped and ambiguous as a player-health source. Session `20260505T002614Z` observed `BP_Destructible_ChaoticBarrel10.HC`, so unscoped `CrabHC` must not be used as the CrabInvSync v2 player health source.
- `CrabHC` read success proves only that the observed component can be read. It does not prove player ownership unless a later discovery phase establishes that relationship.
- `health-playerstate-watch` is a read-only time-series diagnostic for vanilla local PlayerState health visibility.
- RuntimeProbe documents what vanilla exposes. CrabInvSync may later build pooled/shared behavior from reported local state, but pooled/shared health is not vanilla RuntimeProbe evidence.

## Latest Health PlayerState Watch Summary

- Samples: 118
- PlayerState watch probe ran: True
- CrabHC touched: False
- Ambiguous CrabHC detected: False
- Unsafe gates: HUD=false, deepArrays=false, InventoryInfo=false, writes=false, RPCs=false, unknownRole=false, joinedClientDeep=false
- currentHealth first/last/min/max: 250 / 0 / 0 / 250
- currentMaxHealth first/last/min/max: 250 / 0 / 0 / 250
- baseMaxHealth first/last/min/max: 250 / 250 / 250 / 250
- maxHealthMultiplier first/last/min/max: 1 / 1 / 1 / 1
- Possible base health model: local PlayerState base appears 250
- Vanilla local PlayerState health visibility: 250/250 observed during valid samples; BaseMaxHealth stayed 250 and MaxHealthMultiplier stayed 1 in the latest watch evidence.
- Terminal 0/0 was observed; treat it as a likely lifecycle, quit, transition, or despawn artifact unless separately proven.

## Latest Identity Roster Summary

- Local player identity visible: yes
- Max visible player count observed: 2
- Any candidate exposed more than one player: yes
- Source paths observed: CrabGS, CrabPC.PlayerState, CrabPC.PlayerState identity fields, FindAllOf(PlayerController,CrabPC).PlayerState, FindAllOf(PlayerState,CrabPS), GameStateBase, GameStateBase.PlayerArray
- Roster source candidates attempted: Identity.CrabGS.SourceCandidate, Identity.FindAll.PlayerStateCandidates, Identity.GameState.SourceCandidate, Identity.PlayerArray.Shape, Identity.PlayerControllerCandidates, Identity.VisiblePlayers.SourceCandidate
- Raw IDs/names emitted: no; redacted/fingerprinted by default
- Visible roster source resolved: yes
- PlayerState identity reads are safe and redacted; PlayerName and UniqueId can be fingerprinted without emitting raw values.
- Runtime context `solo-or-host` means local-player-present in the current detector; it is not proof of solo and cannot distinguish true solo from multiplayer host-like local context.
- Visible player roster source is confirmed; auto-room grouping still requires matched host and joined-client runs.

## Multiplayer Resource Visibility Summary

- Summary: unresolved; no `multiplayer-resource-visibility-read` evidence has been imported yet.
- Player count sampled: 0
- Raw identity values are not emitted by this summary; PlayerName and UniqueId evidence remains fingerprint-only.
- No writes/RPCs/HUD hooks/deep array element reads/InventoryInfo/Enhancements are part of this phase.

## Confirmed SAFE Access Rows

| Symbol | Access method | Contexts confirmed | Roles confirmed | Runtime status | Last result | Evidence sessions | Notes |
|---|---|---|---|---|---|---|---|
| `CrabHC` | GetFullName | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=CrabHC /Game/Island/Lobby.Lobby:PersistentLevel.BP_Destructible_ChaoticBarrel10.HC |
| `CrabHC` | IsValid | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=true |
| `CrabHC.BaseMaxHealth` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=400.0 |
| `CrabHC.HealthInfo` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=HealthInfo obtained |
| `CrabHC.HealthInfo.CurrentHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=400.0 |
| `CrabHC.HealthInfo.CurrentMaxHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=400.0 |
| `CrabPC.PlayerState` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T034622Z, 20260505T035239Z, 20260505T052110Z | read-only local CrabPC -> PlayerState identity sample; raw values redacted unless allowRawIdentityEvidence=true |
| `CrabPS.AbilityDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Ability_BlackHole nameSource=fullNameFallback objectClass=CrabAbilityDA |
| `CrabPS.BaseMaxHealth` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo` | PlayerStateHealthSample | solo | solo-or-host | SAFE | ok | 20260505T025430Z, 20260505T055346Z | CrabPC -> PlayerState -> CrabPS -> HealthInfo read-only sample |
| `CrabPS.MaxHealthMultiplier` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.MeleeDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Melee_Hammer nameSource=fullNameFallback objectClass=CrabMeleeDA |
| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Weapon_Minigun nameSource=fullNameFallback objectClass=CrabWeaponDA |
| `CrabPS.HealthInfo.CurrentHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo.CurrentMaxHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `PlayerState.Identity` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T034622Z, 20260505T035239Z, 20260505T052110Z | candidate PlayerState display/stable-id fields via GetPropertyValue only; no raw IDs by default |
| `CrabGS` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindFirstOf(CrabGS); GetFullName/GetName/GetClass only; objectdump shows CrabGS extends GameStateBase but no CrabGS-specific PlayerArray property; optional source name/class read error: function: 000002227AAEBC50function: 000002227AAEBC50 |
| `CrabHC` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=CrabHC found |
| `GameStateBase GameState` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindFirstOf(GameStateBase) with GameState fallback; GetFullName/GetName/GetClass only; no roster or property traversal performed; optional source name/class read error: function: 000002227AAEBC50function: 000002227AAEBC50 |
| `PlayerController CrabPC` | FindAllOfCapped | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindAllOf availability checked before capped PlayerController/CrabPC traversal; only PlayerState property was read from valid controllers, cap=8 |
| `PlayerState CrabPS` | FindAllOfCapped | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindAllOf availability checked before capped PlayerState-like candidate traversal; sampled PlayerState and CrabPS only, cap=16, no raw identity by default |
| `Runtime.Context` | observe | lobby, solo, unknown | solo-or-host, unknown | SAFE | ok | 20260505T032627Z | context observation only; not arbitrary object access |
