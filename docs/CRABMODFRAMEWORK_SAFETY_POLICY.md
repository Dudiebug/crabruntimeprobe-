# CrabModFramework Safety Policy

CrabModFramework must be evidence-led. RuntimeProbe evidence can prove that a read path worked under a documented context and gate set. It does not prove that writes, DataAsset mutation, RPC calls, event invocation, or deeper traversal are safe.

## RuntimeProbe Boundaries

RuntimeProbe phases must remain read-only unless a future task explicitly changes the project charter. Current forbidden actions are:

- Property writes.
- RPC calls.
- HUD tick hook use.
- Deep array probes.
- Live inventory array traversal, counting, or element dereference.
- InventoryInfo reads.
- Enhancements reads.
- Arbitrary object graph recursion.
- DataAsset function calls.
- DataAsset mutation.

The `perk-da-catalog-read` phase adds these required markers to probe/access rows: `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noInventoryArrays`, `noArrayCount`, `noArrayTraversal`, `noElementDereference`, `noInventoryInfo`, `noEnhancements`, `noDataAssetMutation`, `noFunctionCalls`, and `passiveOnly`.

The direct `max-safe-play-recorder` profile is a recorder, not a new safety authorization. It may log only already proven-safe scalar paths and capped read-only perk DataAsset catalog snapshots. Its rows must mark `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noInventoryArrays`, `noArrayCount`, `noArrayTraversal`, `noElementDereference`, `noInventoryInfo`, `noEnhancements`, `noDataAssetMutation`, `noFunctionCalls`, and `passiveOnly` as true.

Failed/no-sample recorder runs are failures. If no PlayerState-present scalar samples are collected, the run must be reported with remediation and must not be promoted into confirmed useful evidence.

## Framework Rules

CrabModFramework should prefer high-level Crab Champions APIs backed by RuntimeProbe evidence. Raw UE4SS calls should be wrapped, reviewed, and eventually linted or validated.

Any future write/edit API must be separate from RuntimeProbe, capability-gated, and documented as experimental until dedicated evidence and review exists. DataAsset catalog evidence is read evidence only; it is not permission to mutate DataAssets.

Future live inventory array counts, inventory element DataAsset reads, InventoryInfo, Enhancements, event watchers, and additional DataAsset catalog families may enter the max-safe recorder only after their own dedicated campaign phases prove safety.

## Passive Watchers

Future event/function watchers are passive observe-only tools. They may record what the game naturally calls while Dylan plays. They must not call game functions themselves.

Likely future watch targets include `OnRep_Crystals`, `OnRep_Inventory`, `OnRep_WeaponDA`, `OnRep_AbilityDA`, `OnRep_MeleeDA`, `ClientOnPickedUpPickup`, and `ServerIncrementNumInventorySlots` only when the game naturally calls it.
