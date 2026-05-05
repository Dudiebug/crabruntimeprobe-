# Probe Candidates

## Important Warning

Object dump presence does not mean runtime-safe. Candidates are documentation only until confirmed by ProbeRunner results.

Generated from `objectdump/objectdump_index.json` at 2026-05-04T00:53:15.128Z.

## Core Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `FindFirstOf.CrabPC` | `CrabPC (objectdump discovered)` | objectdump | unverified | `mode = active` | Find the player controller class instance. Observe mode has its own passive context row and does not run this candidate. |
| `CrabPC.IsValid` | `CrabPC (objectdump discovered)` | objectdump | unverified | `mode = active` | Validate the cached CrabPC object before other reads. |
| `CrabPC.GetPropertyValue.PlayerState` | `CrabPC.PlayerState (not discovered in objectdump)` | objectdump | unverified | `mode = active` | Read PlayerState through GetPropertyValue only. |
| `CrabPS.IsValid` | `CrabPS (objectdump discovered)` | objectdump | unverified | `mode = active` | Validate the cached PlayerState object. |

## Equipment Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `CrabPS.GetPropertyValue.WeaponDA` | `CrabPS.WeaponDA (objectdump discovered)` | objectdump | unverified | `mode = active; probeSet includes equipment-read` | Property read candidate only. |
| `CrabPS.DirectField.WeaponDA` | `CrabPS.WeaponDA (objectdump discovered)` | objectdump | unverified | `mode = active; probeSet includes equipment-read` | Direct field candidate must stay separate from GetPropertyValue. |
| `CrabPS.GetPropertyValue.AbilityDA` | `CrabPS.AbilityDA (objectdump discovered)` | objectdump | unverified | `mode = active; probeSet includes equipment-read` | Property read candidate only. |
| `CrabPS.DirectField.AbilityDA` | `CrabPS.AbilityDA (objectdump discovered)` | objectdump | unverified | `mode = active; probeSet includes equipment-read` | Direct field candidate must stay separate from GetPropertyValue. |
| `CrabPS.GetPropertyValue.MeleeDA` | `CrabPS.MeleeDA (objectdump discovered)` | objectdump | unverified | `mode = active; probeSet includes equipment-read` | Property read candidate only. |
| `CrabPS.DirectField.MeleeDA` | `CrabPS.MeleeDA (objectdump discovered)` | objectdump | unverified | `mode = active; probeSet includes equipment-read` | Direct field candidate must stay separate from GetPropertyValue. |

## Inventory Array Shallow Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `CrabPS.GetPropertyValue.WeaponMods` | `CrabPS.WeaponMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | WeaponMods / WeaponModDA; reads the array property only. |
| `WeaponMods.ForEach.CountOnly` | `CrabPS.WeaponMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | WeaponMods / WeaponModDA; count elements without dereferencing slot objects. |
| `WeaponMods.ForEach.FirstElementSeen` | `CrabPS.WeaponMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | WeaponMods / WeaponModDA; record that a first array element wrapper exists without calling get(). |
| `CrabPS.GetPropertyValue.AbilityMods` | `CrabPS.AbilityMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | AbilityMods / AbilityModDA; reads the array property only. |
| `AbilityMods.ForEach.CountOnly` | `CrabPS.AbilityMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | AbilityMods / AbilityModDA; count elements without dereferencing slot objects. |
| `AbilityMods.ForEach.FirstElementSeen` | `CrabPS.AbilityMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | AbilityMods / AbilityModDA; record that a first array element wrapper exists without calling get(). |
| `CrabPS.GetPropertyValue.MeleeMods` | `CrabPS.MeleeMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | MeleeMods / MeleeModDA; reads the array property only. |
| `MeleeMods.ForEach.CountOnly` | `CrabPS.MeleeMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | MeleeMods / MeleeModDA; count elements without dereferencing slot objects. |
| `MeleeMods.ForEach.FirstElementSeen` | `CrabPS.MeleeMods (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | MeleeMods / MeleeModDA; record that a first array element wrapper exists without calling get(). |
| `CrabPS.GetPropertyValue.Perks` | `CrabPS.Perks (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | Perks / PerkDA; reads the array property only. |
| `Perks.ForEach.CountOnly` | `CrabPS.Perks (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | Perks / PerkDA; count elements without dereferencing slot objects. |
| `Perks.ForEach.FirstElementSeen` | `CrabPS.Perks (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | Perks / PerkDA; record that a first array element wrapper exists without calling get(). |
| `CrabPS.GetPropertyValue.Relics` | `CrabPS.Relics (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | Relics / RelicDA; reads the array property only. |
| `Relics.ForEach.CountOnly` | `CrabPS.Relics (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | Relics / RelicDA; count elements without dereferencing slot objects. |
| `Relics.ForEach.FirstElementSeen` | `CrabPS.Relics (objectdump discovered)` | objectdump | unverified | `mode = active; explicit shallow inventory research config` | Relics / RelicDA; record that a first array element wrapper exists without calling get(). |

## Inventory Array Deep Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `WeaponMods.FirstElement.Get` | `CrabWeaponMod (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | WeaponMods / WeaponModDA; risky TArray element dereference. |
| `WeaponMods.FirstElement.IsValid` | `CrabWeaponMod (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | WeaponMods / WeaponModDA; validate dereferenced first slot. |
| `WeaponMods.FirstSlot.GetPropertyValue.WeaponModDA` | `CrabWeaponMod.WeaponModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Property read from dereferenced slot. |
| `WeaponMods.FirstSlot.DirectField.WeaponModDA` | `CrabWeaponMod.WeaponModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Direct field read from dereferenced slot; keep separate from GetPropertyValue. |
| `WeaponMods.FirstDA.GetName` | `CrabWeaponMod.WeaponModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Name read on first DA object after slot/DA validation. |
| `WeaponMods.FirstDA.GetFullName` | `CrabWeaponMod.WeaponModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | FullName read on first DA object after slot/DA validation. |
| `AbilityMods.FirstElement.Get` | `CrabAbilityMod (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | AbilityMods / AbilityModDA; risky TArray element dereference. |
| `AbilityMods.FirstElement.IsValid` | `CrabAbilityMod (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | AbilityMods / AbilityModDA; validate dereferenced first slot. |
| `AbilityMods.FirstSlot.GetPropertyValue.AbilityModDA` | `CrabAbilityMod.AbilityModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Property read from dereferenced slot. |
| `AbilityMods.FirstSlot.DirectField.AbilityModDA` | `CrabAbilityMod.AbilityModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Direct field read from dereferenced slot; keep separate from GetPropertyValue. |
| `AbilityMods.FirstDA.GetName` | `CrabAbilityMod.AbilityModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Name read on first DA object after slot/DA validation. |
| `AbilityMods.FirstDA.GetFullName` | `CrabAbilityMod.AbilityModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | FullName read on first DA object after slot/DA validation. |
| `MeleeMods.FirstElement.Get` | `CrabMeleeMod (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | MeleeMods / MeleeModDA; risky TArray element dereference. |
| `MeleeMods.FirstElement.IsValid` | `CrabMeleeMod (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | MeleeMods / MeleeModDA; validate dereferenced first slot. |
| `MeleeMods.FirstSlot.GetPropertyValue.MeleeModDA` | `CrabMeleeMod.MeleeModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Property read from dereferenced slot. |
| `MeleeMods.FirstSlot.DirectField.MeleeModDA` | `CrabMeleeMod.MeleeModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Direct field read from dereferenced slot; keep separate from GetPropertyValue. |
| `MeleeMods.FirstDA.GetName` | `CrabMeleeMod.MeleeModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Name read on first DA object after slot/DA validation. |
| `MeleeMods.FirstDA.GetFullName` | `CrabMeleeMod.MeleeModDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | FullName read on first DA object after slot/DA validation. |
| `Perks.FirstElement.Get` | `CrabPerk (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Perks / PerkDA; risky TArray element dereference. |
| `Perks.FirstElement.IsValid` | `CrabPerk (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Perks / PerkDA; validate dereferenced first slot. |
| `Perks.FirstSlot.GetPropertyValue.PerkDA` | `CrabPerk.PerkDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Property read from dereferenced slot. |
| `Perks.FirstSlot.DirectField.PerkDA` | `CrabPerk.PerkDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Direct field read from dereferenced slot; keep separate from GetPropertyValue. |
| `Perks.FirstDA.GetName` | `CrabPerk.PerkDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Name read on first DA object after slot/DA validation. |
| `Perks.FirstDA.GetFullName` | `CrabPerk.PerkDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | FullName read on first DA object after slot/DA validation. |
| `Relics.FirstElement.Get` | `CrabRelic (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Relics / RelicDA; risky TArray element dereference. |
| `Relics.FirstElement.IsValid` | `CrabRelic (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Relics / RelicDA; validate dereferenced first slot. |
| `Relics.FirstSlot.GetPropertyValue.RelicDA` | `CrabRelic.RelicDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Property read from dereferenced slot. |
| `Relics.FirstSlot.DirectField.RelicDA` | `CrabRelic.RelicDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Direct field read from dereferenced slot; keep separate from GetPropertyValue. |
| `Relics.FirstDA.GetName` | `CrabRelic.RelicDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | Name read on first DA object after slot/DA validation. |
| `Relics.FirstDA.GetFullName` | `CrabRelic.RelicDA (objectdump discovered)` | objectdump | unverified | `allowDeepArrayProbes = true` | FullName read on first DA object after slot/DA validation. |

## InventoryInfo Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `WeaponMods.FirstSlot.InventoryInfo.DirectField` | `CrabWeaponMod.InventoryInfo (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo direct field candidate from dereferenced slot. |
| `WeaponMods.InventoryInfo.Level` | `CrabInventoryInfo.Level (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `WeaponMods.InventoryInfo.AccumulatedBuff` | `CrabInventoryInfo.AccumulatedBuff (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `WeaponMods.InventoryInfo.Enhancements` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo enhancements array candidate. |
| `WeaponMods.Enhancements.ForEach.CountOnly` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | Count enhancements without deep dereference. |
| `AbilityMods.FirstSlot.InventoryInfo.DirectField` | `CrabAbilityMod.InventoryInfo (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo direct field candidate from dereferenced slot. |
| `AbilityMods.InventoryInfo.Level` | `CrabInventoryInfo.Level (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `AbilityMods.InventoryInfo.AccumulatedBuff` | `CrabInventoryInfo.AccumulatedBuff (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `AbilityMods.InventoryInfo.Enhancements` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo enhancements array candidate. |
| `AbilityMods.Enhancements.ForEach.CountOnly` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | Count enhancements without deep dereference. |
| `MeleeMods.FirstSlot.InventoryInfo.DirectField` | `CrabMeleeMod.InventoryInfo (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo direct field candidate from dereferenced slot. |
| `MeleeMods.InventoryInfo.Level` | `CrabInventoryInfo.Level (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `MeleeMods.InventoryInfo.AccumulatedBuff` | `CrabInventoryInfo.AccumulatedBuff (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `MeleeMods.InventoryInfo.Enhancements` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo enhancements array candidate. |
| `MeleeMods.Enhancements.ForEach.CountOnly` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | Count enhancements without deep dereference. |
| `Perks.FirstSlot.InventoryInfo.DirectField` | `CrabPerk.InventoryInfo (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo direct field candidate from dereferenced slot. |
| `Perks.InventoryInfo.Level` | `CrabInventoryInfo.Level (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `Perks.InventoryInfo.AccumulatedBuff` | `CrabInventoryInfo.AccumulatedBuff (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `Perks.InventoryInfo.Enhancements` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo enhancements array candidate. |
| `Perks.Enhancements.ForEach.CountOnly` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | Count enhancements without deep dereference. |
| `Relics.FirstSlot.InventoryInfo.DirectField` | `CrabRelic.InventoryInfo (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo direct field candidate from dereferenced slot. |
| `Relics.InventoryInfo.Level` | `CrabInventoryInfo.Level (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `Relics.InventoryInfo.AccumulatedBuff` | `CrabInventoryInfo.AccumulatedBuff (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo scalar field candidate. |
| `Relics.InventoryInfo.Enhancements` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | InventoryInfo enhancements array candidate. |
| `Relics.Enhancements.ForEach.CountOnly` | `CrabInventoryInfo.Enhancements (objectdump discovered)` | objectdump | unverified | `allowInventoryInfoProbes = true` | Count enhancements without deep dereference. |

## Roster Identity Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `Identity.GameState.SourceCandidate` | `GameStateBase / GameState (objectdump discovered)` | objectdump | unverified | `allowIdentityProbes = true` | FindFirstOf source identity only: GetFullName/GetName/GetClass, no roster traversal. |
| `Identity.CrabGS.SourceCandidate` | `CrabGS (objectdump discovered)` | objectdump | unverified | `allowIdentityProbes = true` | FindFirstOf CrabGS source identity only. Objectdump shows CrabGS extends GameStateBase; no CrabGS-specific PlayerArray field was found. |
| `Identity.PlayerArray.Shape` | `GameStateBase.PlayerArray (objectdump discovered)` | objectdump | unverified | `allowIdentityProbes = true` | Shape-only PlayerArray probe records nil/userdata/table/unsupported and samples table length up to cap without recursive traversal. |
| `Identity.VisiblePlayers.SourceCandidate` | `GameStateBase.PlayerArray (objectdump discovered)` | objectdump | unverified | `allowIdentityProbes = true` | Capped read-only PlayerArray identity candidate. Emits only fingerprints/redacted identity values; raw identity remains disabled by default. |
| `Identity.FindAll.PlayerStateCandidates` | `PlayerState / CrabPS (objectdump discovered)` | objectdump | unverified | `allowIdentityProbes = true` | FindAllOf availability checked first, then capped PlayerState-like candidates only; no arbitrary property dumping. |
| `Identity.PlayerControllerCandidates` | `PlayerController / CrabPC (objectdump discovered)` | objectdump | unverified | `allowIdentityProbes = true` | FindAllOf availability checked first, then capped controller candidates; reads only PlayerState from valid controllers. |

## Health Probes

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `CrabPS.GetPropertyValue.HealthInfo` | `CrabPS.HealthInfo (objectdump discovered)` | objectdump | unverified | `allowHealthProbes = true` | HealthInfo candidate; disabled until explicit health probe phase. |
| `CrabHC.GetPropertyValue.HealthInfo` | `CrabHC.HealthInfo (objectdump discovered)` | objectdump | unverified | `allowHealthProbes = true` | Health component HealthInfo candidate. |
| `CrabHC.GetPropertyValue.OwningC` | `CrabHC.OwningC (objectdump discovered)` | objectdump | unverified | `allowHealthProbes = true` | Health owner candidate. |

## RPC Dry-Run Candidates

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `FunctionPresence.ServerEquipInventory` | `ServerEquipInventory (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerSetWeaponDA` | `ServerSetWeaponDA (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerSetAbilityDA` | `ServerSetAbilityDA (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerSetMeleeDA` | `ServerSetMeleeDA (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerIncrementNumInventorySlots` | `ServerIncrementNumInventorySlots (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerRemoveWeaponMod` | `ServerRemoveWeaponMod (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerRemoveAbilityMod` | `ServerRemoveAbilityMod (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerRemoveMeleeMod` | `ServerRemoveMeleeMod (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerRemovePerk` | `ServerRemovePerk (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ServerRemoveRelic` | `ServerRemoveRelic (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.OnRep_Inventory` | `OnRep_Inventory (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.OnRep_Crystals` | `OnRep_Crystals (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.OnRep_WeaponDA` | `OnRep_WeaponDA (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.OnRep_AbilityDA` | `OnRep_AbilityDA (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.OnRep_MeleeDA` | `OnRep_MeleeDA (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ClientRefreshPSUI` | `ClientRefreshPSUI (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |
| `FunctionPresence.ClientOnPickedUpPickup` | `ClientOnPickedUpPickup (objectdump discovered)` | objectdump | unverified | `allowRpcProbes = true` | Documentation-only function presence candidate. Do not call mutating RPCs. |

## Write-Unsafe Candidates

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `DoNotCall.ServerEquipInventory` | `ServerEquipInventory (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerSetWeaponDA` | `ServerSetWeaponDA (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerSetAbilityDA` | `ServerSetAbilityDA (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerSetMeleeDA` | `ServerSetMeleeDA (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerIncrementNumInventorySlots` | `ServerIncrementNumInventorySlots (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerRemoveWeaponMod` | `ServerRemoveWeaponMod (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerRemoveAbilityMod` | `ServerRemoveAbilityMod (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerRemoveMeleeMod` | `ServerRemoveMeleeMod (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerRemovePerk` | `ServerRemovePerk (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |
| `DoNotCall.ServerRemoveRelic` | `ServerRemoveRelic (objectdump discovered)` | objectdump | unverified | `not allowed` | Mutating server/write path. Document only; do not implement as a runtime probe. |

## Unknown

| Probe id | Related objectdump symbol | Source | Runtime status | Required safety gate | Notes |
|---|---|---|---|---|---|
| `FindFirstOf.CrabGS` | `CrabGS (objectdump discovered)` | objectdump | unverified | `none; documentation only` | Objectdump symbol of interest with no runtime access plan yet. |
| `FindFirstOf.CrabAutoSave` | `CrabAutoSave (objectdump discovered)` | objectdump | unverified | `none; documentation only` | Objectdump symbol of interest with no runtime access plan yet. |
| `FindFirstOf.CrabInteractPickup` | `CrabInteractPickup (objectdump discovered)` | objectdump | unverified | `none; documentation only` | Objectdump symbol of interest with no runtime access plan yet. |
| `FindFirstOf.CrabPickupInfo` | `CrabPickupInfo (objectdump discovered)` | objectdump | unverified | `none; documentation only` | Objectdump symbol of interest with no runtime access plan yet. |
| `FindFirstOf.CrabInventorySlotUI` | `CrabInventorySlotUI (objectdump discovered)` | objectdump | unverified | `none; documentation only` | Objectdump symbol of interest with no runtime access plan yet. |

## How to Enable Later

- Keep default `mode = observe` for first in-game tests.
- Switch to `mode = active` only after observe rows are stable and reviewed.
- Enable deep inventory candidates only with `allowDeepArrayProbes = true`.
- Enable InventoryInfo candidates only with `allowInventoryInfoProbes = true`.
- Enable health candidates only with `allowHealthProbes = true`.
- Enable roster identity candidates only with `allowIdentityProbes = true`; keep `allowRawIdentityEvidence = false` unless private evidence capture is explicitly requested.
- Do not implement or call write-unsafe or mutating RPC candidates in CrabRuntimeProbe.
