# CrabModFramework API Contract

This is a proposed API contract style for future CrabModFramework work. It is not implementation, does not prove CrabModFramework exists as runtime code today, and does not authorize RuntimeProbe writes, mutating RPCs, or CrabSyncV2 implementation.

## 1. Purpose

Define the contract style future CrabModFramework APIs should follow so consuming mods can use evidence-backed wrappers instead of raw UE4SS calls.

APIs described here are proposed contracts for future work. They name wrapper responsibilities, result shapes, and safety boundaries only.

## 2. Contract Principles

- Every function returns status, value, and source proof.
- No raw UE4SS errors should bubble into consuming mods.
- No crashy object operations are exposed directly.
- Every access maps to evidence status.
- Capability declarations are required.
- Experimental writes are separate from read APIs.
- RuntimeProbe remains the evidence source, not a runtime dependency for all mods unless explicitly designed.

## 3. Proposed Modules

### Context

Reports role, lifecycle, generation, and stable/unstable status. It is the first gate before any risky read or future apply path.

### PlayerState

Provides local PlayerState access, visible remote PlayerState access, and identity fingerprinting/redaction. Raw identity values are not normal API output.

### Resources

Reads crystals and slots through proven paths. Keys policy is disabled/out of scope unless explicitly re-approved.

### Equipment

Reads `WeaponDA`, `AbilityDA`, and `MeleeDA` identities through proven PlayerState-scoped paths.

### Health

Reads PlayerState-scoped `HealthInfo`, `CurrentHealth`, `CurrentMaxHealth`, `BaseMaxHealth`, and `MaxHealthMultiplier`. Armor remains unresolved.

### InventoryRead

Covers array shape, count metadata, first item identity in a future gated phase, `InventoryInfo` in a future gated phase, `Enhancements` in a future gated phase, and duplicate semantics in future proof phases.

### DataAssets

Provides catalog reads, the current Perk catalog, and future weapon/ability/melee/mod/relic catalogs after dedicated proof.

### P2P

Provides visible-state convergence helpers, future carrier read helpers, and no carrier write unless an experimental capability exists.

### Events

Provides passive event observation wrappers. It does not call game functions by default.

### Diagnostics

Emits evidence status, skip reasons, unsafe reasons, stale reasons, and structured logs.

### ExperimentalWrite

Future-only, disabled by default, and separate from RuntimeProbe. It requires safe write-path discovery, explicit user approval, and sandbox evidence before any narrow use.

## 4. Proposed Pseudo-API Shapes

These signatures are non-implementation examples. Each result includes `status`, `value`, `sourceProof`, `lifecycle`, `role`, and `safetyNotes`.

| Pseudo-API | Purpose | Result Shape |
|---|---|---|
| `Context.getState()` | Read role, lifecycle, generation, and stability. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `PlayerState.getLocal()` | Get local PlayerState through a proven wrapper. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `PlayerState.getVisiblePlayers()` | Get visible/fingerprinted player rows. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `Equipment.readLocal()` | Read local equipment DA identities. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `Equipment.readVisible()` | Read visible remote equipment DA identities where proven. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `Resources.readCrystals()` | Read crystal scalar through scoped capability. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `Resources.readSlots()` | Read slot scalar counters through scoped capability. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `Health.readSnapshot()` | Read PlayerState-scoped health snapshot. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `InventoryRead.readArrayShape()` | Read local inventory property shape. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `InventoryRead.readArrayCount()` | Read wrapper count metadata only. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `InventoryRead.readFirstItemIdentity()` | Future gated first-item identity read. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `InventoryRead.readInventoryInfo()` | Future gated metadata scalar read. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `InventoryRead.readEnhancements()` | Future gated enhancement read. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `P2P.readCarrier()` | Future gated carrier read. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `Diagnostics.emitSkip()` | Emit structured skip reason. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |
| `ExperimentalWrite.planOnly()` | Future gated plan-only write/apply analysis. | `{ status, value, sourceProof, lifecycle, role, safetyNotes }` |

`planOnly()` does not write. Read APIs never apply state.

## 5. Error Handling Contract

Wrappers catch unsafe, nil, error, stale, and unsupported states and return status objects rather than throwing into consuming mods.

Wrappers should return `unsupported`, `unsafe`, or `stale` rather than retrying dangerous paths.

`crash-suspect` escalates to suspension.

Repeated errors lower confidence and should not trigger broad retry loops.

No broad retry loops may increase access risk.

## 6. Apply/Write Contract Boundary

Read APIs never apply.

An apply planner does not write.

An apply executor is future/experimental.

A write executor cannot exist until write-path docs and sandbox evidence exist.

No production writes may be based on objectdump-only or function-presence-only evidence.

## 7. Compatibility With CrabSyncV2

CrabSyncV2 should consume future CrabModFramework modules rather than raw UE4SS access where possible:

- `Context`: lifecycle, role, generation, and suspension decisions.
- `PlayerState`: local/visible player rows and redacted fingerprints.
- `Health`: PlayerState-scoped read-only snapshots.
- `Resources`: crystals and slots with keys excluded.
- `Equipment`: local and visible equipment DA identities.
- `InventoryRead`: proof-ladder inventory reads only.
- `P2P`: visible-state convergence helpers and future carrier reads.
- `Diagnostics`: skip, unsupported, unsafe, and crash-suspect logging.
- `ExperimentalWrite`: future only, disabled until write-path and sandbox gates exist.
