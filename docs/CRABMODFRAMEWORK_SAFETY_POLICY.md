# CrabModFramework Safety Policy

CrabModFramework must be evidence-led. RuntimeProbe evidence can prove that a read path worked under a documented context and gate set. It does not prove that writes, DataAsset mutation, RPC calls, event invocation, or deeper traversal are safe.

Future mod authors should follow [CrabModFramework Modding Guide](CRABMODFRAMEWORK_MODDING_GUIDE.md). Future wrapper contracts and capability declarations are defined in [CrabModFramework API Contract](CRABMODFRAMEWORK_API_CONTRACT.md) and [CrabModFramework Capability Model](CRABMODFRAMEWORK_CAPABILITY_MODEL.md). These docs are planning contracts, not implementation.

## RuntimeProbe Boundaries

RuntimeProbe phases must remain read-only unless a future task explicitly changes the project charter. Current forbidden actions are:

- Property writes.
- RPC calls.
- HUD tick hook use.
- Deep array probes.
- Live inventory array traversal or element dereference, except the capped first-element identity attempt in the narrow `inventory-element-da-read` phase.
- Live inventory array counting except the narrow `inventory-array-count-read` wrapper metadata phase.
- InventoryInfo reads.
- Enhancements reads.
- Arbitrary object graph recursion.
- DataAsset function calls.
- DataAsset mutation.

The `perk-da-catalog-read` phase adds these required markers to probe/access rows: `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noInventoryArrays`, `noArrayCount`, `noArrayTraversal`, `noElementDereference`, `noInventoryInfo`, `noEnhancements`, `noDataAssetMutation`, `noFunctionCalls`, and `passiveOnly`.

The direct `max-safe-play-recorder` profile is a recorder, not a new safety authorization. It may log only already proven-safe scalar paths and capped read-only perk DataAsset catalog snapshots. Its rows must mark `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noInventoryArrays`, `noArrayCount`, `noArrayTraversal`, `noElementDereference`, `noInventoryInfo`, `noEnhancements`, `noDataAssetMutation`, `noFunctionCalls`, and `passiveOnly` as true.

Failed/no-sample recorder runs are failures. If no PlayerState-present scalar samples are collected, the run must be reported with remediation and must not be promoted into confirmed useful evidence.

The `inventory-array-count-read` phase is a narrow read-only proof for local PlayerState inventory wrapper count metadata only. It reads only `WeaponMods`, `AbilityMods`, `MeleeMods`, `Perks`, and `Relics` with `GetPropertyValue`, then attempts only a protected Lua length operation on the returned wrapper. Its required markers include `noInventoryTraversal`, `noArrayTraversal`, `noElementDereference`, `noItemDataAssetRead`, `noInventoryInfo`, `noEnhancements`, `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noDataAssetMutation`, and `passiveOnly`.

Count evidence is not traversal evidence, item sync evidence, item DataAsset evidence, InventoryInfo evidence, or Enhancements evidence. It does not authorize item element reads outside the separately gated `inventory-element-da-read` phase.

The `inventory-element-da-read` phase is a narrow read-only proof for capped local inventory element identity only. It may read the same five local array properties, use prior count metadata, and consider at most one first element per non-empty array. If no vetted first-element access helper exists, it must report `inventory_element_da_unsupported` instead of trying multiple risky access methods. Its required markers include `noBroadDeepArrays`, `noArrayTraversal`, `noFullArrayIteration`, `cappedElementAccess`, `maxElementsPerArray = 1`, `noInventoryInfo`, `noEnhancements`, `noLevelRead`, `noAccumulatedBuffRead`, `noDataAssetMutation`, `noFunctionCalls`, and `passiveOnly`.

Element DA evidence is not full inventory sync evidence, InventoryInfo evidence, Enhancement evidence, Level evidence, AccumulatedBuff evidence, or proof that full traversal is safe.

## Framework Rules

CrabModFramework should prefer high-level Crab Champions APIs backed by RuntimeProbe evidence. Raw UE4SS calls should be wrapped, reviewed, and eventually linted or validated.

Any future write/edit API must be separate from RuntimeProbe, capability-gated, and documented as experimental until dedicated evidence and review exists. DataAsset catalog evidence is read evidence only; it is not permission to mutate DataAssets.

Unsupported, unavailable, unsafe, stale, and crash-suspect wrapper results must produce skip/suspend behavior. They must not fall back to broad object crawling, direct inventory metadata access, mutating RPCs, or raw writes.

Future InventoryInfo, Enhancements, event watchers, and additional DataAsset catalog families may enter the max-safe recorder only after their own dedicated campaign phases prove safety. Inventory wrapper count metadata and inventory element identity reads can enter later only after their phases produce clean evidence and the recorder is explicitly updated.

## Passive Watchers

Future event/function watchers are passive observe-only tools. They may record what the game naturally calls while Dylan plays. They must not call game functions themselves.

Likely future watch targets include `OnRep_Crystals`, `OnRep_Inventory`, `OnRep_WeaponDA`, `OnRep_AbilityDA`, `OnRep_MeleeDA`, `ClientOnPickedUpPickup`, and `ServerIncrementNumInventorySlots` only when the game naturally calls it.
