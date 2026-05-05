# Runtime Evidence Index

Generated from imported runtime evidence under `evidence/runtime/`.

- Access evidence files: 13
- Probe result files: 13
- Diagnostic summaries: 12
- Evidence rows: 303
- Health playerstate watch samples: 200
- Identity/roster samples: 15
- Resource visibility samples: 6
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

- Samples: 0
- PlayerState watch probe ran: False
- CrabHC touched: False
- Ambiguous CrabHC detected: False
- Unsafe gates: HUD=false, deepArrays=false, InventoryInfo=false, writes=false, RPCs=false, unknownRole=false, joinedClientDeep=false
- currentHealth first/last/min/max: not found / not found / not found / not found
- currentMaxHealth first/last/min/max: not found / not found / not found / not found
- baseMaxHealth first/last/min/max: not found / not found / not found / not found
- maxHealthMultiplier first/last/min/max: not found / not found / not found / not found
- Possible base health model: unknown
- Vanilla local PlayerState health visibility: 250/250 observed during valid samples; BaseMaxHealth stayed 250 and MaxHealthMultiplier stayed 1 in the latest watch evidence.
- Terminal 0/0 was not observed in the latest watch summary.

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
- Raw identity values are not emitted by this summary; PlayerName and UniqueId evidence remains fingerprint-only.
- No writes/RPCs/HUD hooks/deep array element reads/InventoryInfo/Enhancements are part of this phase.

## Local Inventory Array Shallow/Count Visibility Summary

- Summary: local_inventory_shape_visible_crash_suspect
- Local inventory array status: crash_suspect_local_inventory_shape_visible
- Local PlayerState present: yes
- Fields readable by shallow shape/count: AbilityMods, MeleeMods, Perks, Relics, WeaponMods
- Fields nil or unsupported: none
- Array value kinds: AbilityMods=userdata, MeleeMods=userdata, Perks=userdata, Relics=userdata, WeaponMods=userdata
- Array counts available: no; current helper only counts Lua tables and these values were userdata shapes
- Slot scalar values: NumAbilityModSlots=12, NumMeleeModSlots=12, NumPerkSlots=24, NumWeaponModSlots=24
- Array elements dereferenced: no
- A crash dump exists after this run, so this path remains crash-suspect pending another safer confirmation pass.
- Local inventory array visibility is separate from remote PlayerState inventory array visibility.
- InventoryInfo and Enhancements were not read; writes/RPCs/HUD hooks/deep arrays were disabled.
- Remote inventory array visibility remains unresolved separately.

## Local Inventory Array Shape Confirm Summary

- Summary: local_inventory_shape_confirmed
- Local inventory shape confirm status: local_inventory_shape_confirmed
- Local PlayerState present: yes
- Fields readable by property shape confirm: AbilityMods, MeleeMods, Perks, Relics, WeaponMods
- Fields nil or unsupported: none
- Property present map: AbilityMods=true, MeleeMods=true, Perks=true, Relics=true, WeaponMods=true
- Array value kinds: AbilityMods=userdata, MeleeMods=userdata, Perks=userdata, Relics=userdata, WeaponMods=userdata
- Safe tostring kinds: AbilityMods=string, MeleeMods=string, Perks=string, Relics=string, WeaponMods=string
- Slot scalar values: NumAbilityModSlots=12, NumMeleeModSlots=12, NumPerkSlots=24, NumWeaponModSlots=24
- Array counts attempted: no
- Array traversal attempted: no
- Array elements dereferenced: no
- InventoryInfo read: no
- Enhancements read: no
- No crash dump is associated with the imported shape-confirm evidence.
- Shape confirm distinguishes userdata shape visibility from countable Lua table arrays; counts remain unavailable for userdata values.

## Local Inventory Userdata Introspection Summary

- Summary: local_inventory_userdata_introspection_confirmed
- Local inventory userdata introspection status: local_inventory_userdata_introspection_confirmed
- Local PlayerState present: yes
- Fields readable by userdata introspection: AbilityMods, MeleeMods, Perks, Relics, WeaponMods
- Value kinds: AbilityMods=userdata, MeleeMods=userdata, Perks=userdata, Relics=userdata, WeaponMods=userdata
- Safe tostring kinds: AbilityMods=string, MeleeMods=string, Perks=string, Relics=string, WeaponMods=string
- Metatable kinds: AbilityMods=boolean, MeleeMods=boolean, Perks=boolean, Relics=boolean, WeaponMods=boolean
- Length operator attempted: AbilityMods=true, MeleeMods=true, Perks=true, Relics=true, WeaponMods=true
- Length operator results: AbilityMods=0, MeleeMods=0, Perks=0, Relics=0, WeaponMods=1
- Length operator errors: none
- Array traversal attempted: no
- Array elements dereferenced: no
- InventoryInfo read: no
- Enhancements read: no
- Writes/RPCs: no
- Length operator results, if present, are metadata-only and do not prove count traversal, element traversal, or item sync.

## Local Crystals Read Summary

- Summary: unresolved; no `crystals-read` evidence has been imported yet.
- Crystals-read will read only local `CrabPC -> PlayerState -> CrabPS -> Crystals`.
- UInt32 range is documentation only; RuntimeProbe does not write or clamp values.

## Local Slots Read Summary

- Summary: unresolved; no `slots-read` evidence has been imported yet.
- Slots-read will read only local `CrabPC -> PlayerState -> CrabPS` scalar fields: `NumWeaponModSlots`, `NumAbilityModSlots`, `NumMeleeModSlots`, `NumPerkSlots`.
- ByteProperty range 0..255 is documentation only; RuntimeProbe does not write or clamp values.
- Locked slots remain unresolved; no separate locked/max/total slot-capacity field was found in the tracked objectdump-derived notes.

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
| `CrabPS.Crystals` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T063937Z | Read-only Crystals and optional Keys scalar visibility checks |
| `CrabPS.HealthInfo` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo` | PlayerStateHealthSample | solo | solo-or-host | SAFE | ok | 20260505T025430Z, 20260505T055346Z | CrabPC -> PlayerState -> CrabPS -> HealthInfo read-only sample |
| `CrabPS.HealthInfo` | RemotePlayerStateHealthSample | solo | solo-or-host | SAFE | ok | 20260505T063937Z | Read-only HealthInfo.CurrentHealth/CurrentMaxHealth plus BaseMaxHealth/MaxHealthMultiplier checks from visible PlayerStates; no CrabHC touched |
| `CrabPS.MaxHealthMultiplier` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.MeleeDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z | sourceScope=player_state_scoped; shortName=DA_Melee_Hammer nameSource=fullNameFallback objectClass=CrabMeleeDA |
| `CrabPS.NumWeaponModSlots` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T063937Z, 20260505T072250Z | Read-only NumWeaponModSlots/NumAbilityModSlots/NumMeleeModSlots/NumPerkSlots visibility checks; Read-only local CrabPC -> PlayerState slot scalar sample for inventory array correlation |
| `CrabPS.WeaponDA` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260504T235201Z, 20260505T063937Z | Read-only WeaponDA/AbilityDA/MeleeDA property visibility checks; object identities are not dereferenced or summarized in this phase |
| `CrabPS.WeaponMods` | GetPropertyValueCountOnly | solo | solo-or-host | SAFE | ok | 20260505T063937Z, 20260505T072250Z | Count-only local inventory array check; table counts are capped and elements are never dereferenced; Read-only count-only checks for WeaponMods/AbilityMods/MeleeMods/Perks/Relics; no element dereference, InventoryInfo, or Enhancements |
| `CrabPS.WeaponMods` | GetPropertyValueShapeConfirm | solo | solo-or-host | SAFE | ok | 20260505T204615Z | Read-only local CrabPC -> PlayerState -> CrabPS property shape confirm; no count, traversal, element dereference, InventoryInfo, Enhancements, writes, or RPCs |
| `CrabPS.WeaponMods` | GetPropertyValueShapeOnly | solo | solo-or-host | SAFE | ok | 20260505T072250Z | Read-only local CrabPC -> PlayerState -> CrabPS array shape check; no element dereference, InventoryInfo, Enhancements, writes, or RPCs |
| `CrabPS.WeaponMods` | GetPropertyValueUserdataMetadata | solo | solo-or-host | SAFE | ok | 20260505T225501Z | Read-only local CrabPC -> PlayerState -> CrabPS userdata wrapper metadata; no traversal, element dereference, InventoryInfo, Enhancements, writes, RPCs, HUD, or deep arrays |
| `CrabPS.HealthInfo.CurrentHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `CrabPS.HealthInfo.CurrentMaxHealth` | HealthInfoStructField | solo | solo-or-host | SAFE | ok | 20260505T002614Z, 20260505T010858Z | CrabPC -> PlayerState -> CrabPS health path |
| `PlayerState.Identity` | GetPropertyValue | solo | solo-or-host | SAFE | ok | 20260505T034622Z, 20260505T035239Z, 20260505T052110Z, 20260505T063937Z | Capped read-only visible PlayerState/CrabPS candidate identity fingerprints; no raw names or UniqueIds emitted; candidate PlayerState display/stable-id fields via GetPropertyValue only; no raw IDs by default |
| `CrabGS` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindFirstOf(CrabGS); GetFullName/GetName/GetClass only; objectdump shows CrabGS extends GameStateBase but no CrabGS-specific PlayerArray property; optional source name/class read error: function: 000002227AAEBC50function: 000002227AAEBC50 |
| `CrabHC` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T002614Z | sourceScope=non_player_candidate; value=CrabHC found |
| `GameStateBase GameState` | FindFirstOf | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindFirstOf(GameStateBase) with GameState fallback; GetFullName/GetName/GetClass only; no roster or property traversal performed; optional source name/class read error: function: 000002227AAEBC50function: 000002227AAEBC50 |
| `PlayerController CrabPC` | FindAllOfCapped | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindAllOf availability checked before capped PlayerController/CrabPC traversal; only PlayerState property was read from valid controllers, cap=8 |
| `PlayerState CrabPS` | FindAllOfCapped | solo | solo-or-host | SAFE | ok | 20260505T052110Z | FindAllOf availability checked before capped PlayerState-like candidate traversal; sampled PlayerState and CrabPS only, cap=16, no raw identity by default |
| `Runtime.Context` | observe | lobby, solo, unknown | solo-or-host, unknown | SAFE | ok | 20260505T032627Z | context observation only; not arbitrary object access |
