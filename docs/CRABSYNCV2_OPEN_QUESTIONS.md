# CrabSyncV2 Open Questions

This is a living research backlog for CrabSyncV2 planning. Status values reflect current imported RuntimeProbe evidence, not hopes.

| Question | Why it matters | Current evidence status | Safest next RuntimeProbe phase | Blocked CrabSyncV2 decision | Risk level |
|---|---|---|---|---|---|
| Can local inventory userdata expose a safe count? | Count is needed before any item diff. | Unresolved; shape visible as userdata, count unavailable/metadata only. | Local inventory count strategy proof. | Inventory read model. | High |
| Can local inventory userdata expose safe element wrappers? | Wrapper visibility precedes dereference. | Not proven. | Local first-element wrapper proof. | Item iteration design. | High |
| Can first element be dereferenced safely? | Required for item metadata. | Not proven. | Local first-element dereference proof. | Item reader feasibility. | Critical |
| Can DA identity be read safely from item structs? | Needed for stable item identity. | Equipment DAs proven; item DAs not proven. | Local DA identity read proof. | Item identity schema. | High |
| Can `InventoryInfo` be read safely? | Needed for level/buff metadata. | Not proven. | Local InventoryInfo scalar read proof. | Metadata preservation. | Critical |
| Can `Enhancements` be read safely? | Needed for Anvil upgrades. | Not proven. | Local Enhancements shape/count proof, then value proof. | Upgrade preservation. | Critical |
| Can joined clients safely perform the same reads? | Local solo proof is not joined-client proof. | Not proven for deep inventory reads. | Joined-client read-only replay of each proven local phase. | Joined-client reader enablement. | Critical |
| Can remote PlayerStates expose inventory arrays or item metadata? | Determines whether P2P inventory visibility exists. | Remote inventory remains unresolved/partial; metadata unproven. | Remote PlayerState inventory visibility research. | P2P vs relay inventory design. | High |
| Do we need a relay/server for inventory? | May be required if metadata is local-only. | Unknown. | Remote visibility research after local item metadata proof. | Networking architecture. | High |
| Can equipment be synced using official setters/RPCs? | Official paths may be safer than raw writes. | Function presence is objectdump/candidate only; calls untested. | CrabSyncV2-only RPC/write sandbox design. | Equipment apply executor. | Critical |
| Can slots use `ServerIncrementNumInventorySlots`? | Slot sync may need official mutation. | Objectdump/candidate only; mutating call untested. | CrabSyncV2-only RPC sandbox. | Slot apply strategy. | Critical |
| Should keys sync? | Key sharing changes gameplay and may be unsafe. | Visibility mentioned, policy unresolved. | Resource visibility follow-up. | Resource merge scope. | Medium |
| Should armor plates sync? | Armor affects survivability and pooling rules. | Not documented as proven. | Health multiplayer watch plus armor-specific evidence. | Armor policy. | High |
| How should health pooling work with multiple players? | Pooling is design behavior, not vanilla fact. | Local PlayerState health proven; multiplayer math unresolved. | Health multiplayer watch. | Health merge model. | High |
| How do we detect player-owned `CrabHC` safely? | Avoids destructible/barrel components. | Unscoped `CrabHC` ambiguous. | Player-owned CrabHC discovery. | Health component fallback. | High |
| Does `StartingWeaponMod` cause duplicate weapon mod application? | Avoid duplicate grants on apply. | Not proven in RuntimeProbe evidence. | Future item/apply sandbox, not RuntimeProbe default. | Weapon mod apply policy. | Medium |
| Do raw inventory writes stale `InventoryCooldowns`? | Raw writes may desync hidden state/UI. | Unknown and write-unsafe. | CrabSyncV2-only write sandbox after reads. | Raw write fallback viability. | Critical |
| What exact state resets are needed after join/travel/respawn? | Prevent stale client/apply state. | General lifecycle risk known; exact reset set not proven. | Lifecycle transition observe/read-only diagnostics. | State machine reset policy. | High |
