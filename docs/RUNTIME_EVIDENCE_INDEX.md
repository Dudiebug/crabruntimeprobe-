# Runtime Evidence Index

Generated from imported runtime evidence under `evidence/runtime/`.

- Access evidence files: 3
- Probe result files: 3
- Diagnostic summaries: 2
- Evidence rows: 20
- Health playerstate watch samples: 0
- Objectdump symbols discovered: 0

- Probe candidates doc present: yes

Objectdump discovery means a symbol exists in static dump data. It does not mean runtime access is safe.

## Health Source Scope Notes

- `CrabPS` health rows are player-state-scoped because the probe path starts from `CrabPC -> PlayerState -> CrabPS`.
- `CrabPC -> PlayerState -> CrabPS -> HealthInfo` is the only currently confirmed safe player health read path.
- `FindFirstOf.CrabHC` is unscoped and ambiguous as a player-health source. Session `20260505T002614Z` observed `BP_Destructible_ChaoticBarrel10.HC`, so unscoped `CrabHC` must not be used as the CrabInvSync v2 player health source.
- `CrabHC` read success proves only that the observed component can be read. It does not prove player ownership unless a later discovery phase establishes that relationship.
- `health-playerstate-watch` is a read-only time-series diagnostic. Do not infer CrabInvSync v2 health math from a single static health snapshot.
- Multiplayer health scaling remains unproven until watch evidence exists from multiplayer scenarios.

## Confirmed SAFE Access Rows

| Symbol | Access method | Contexts confirmed | Roles confirmed | Runtime status | Last result | Evidence sessions | Notes |
|---|---|---|---|---|---|---|---|
| `CrabHC` | GetFullName | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=CrabHC /Game/Island/Lobby.Lobby:PersistentLevel.BP_Destructible_ChaoticBarrel10.HC |
| `CrabHC` | IsValid | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=true |
| `CrabHC.BaseMaxHealth` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=400.0 |
| `CrabHC.HealthInfo` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=HealthInfo obtained |
| `CrabHC.HealthInfo.CurrentHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=400.0 |
| `CrabHC.HealthInfo.CurrentMaxHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=400.0 |
| `CrabPS.AbilityDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Ability_BlackHole nameSource=fullNameFallback objectClass=CrabAbilityDA |
| `CrabPS.BaseMaxHealth` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.MaxHealthMultiplier` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.MeleeDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Melee_Hammer nameSource=fullNameFallback objectClass=CrabMeleeDA |
| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Weapon_Minigun nameSource=fullNameFallback objectClass=CrabWeaponDA |
| `CrabPS.HealthInfo.CurrentHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo.CurrentMaxHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabHC` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=CrabHC found |
