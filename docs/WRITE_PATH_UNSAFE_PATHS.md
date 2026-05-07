# Write Path Unsafe Paths

This is a future status document for write paths that are unsafe, forbidden, or blocked. A path may be safe to read but unsafe to write. A path may be useful for P2P derivation but unsafe for mutation.

RuntimeProbe remains read-only. This document does not authorize writes, RPC calls, or CrabSyncV2 implementation.

[Write Path Evidence Mapping](WRITE_PATH_EVIDENCE_MAPPING.md) defines how future passive evidence and rejection rows map into this unsafe-path list. Unsafe write status does not erase confirmed safe read evidence.

## 1. Purpose

The purpose of this document is to keep rejected write/apply paths visible so they are not accidentally promoted from read evidence, objectdump symbols, or v1 prototype behavior.

## 2. Unsafe Reason Taxonomy

- `gameplay-authoritative`
- `currency/progression`
- `identity/matchmaking`
- `save-persistent`
- `health/gameplay-critical`
- `equipment authority`
- `inventory authority`
- `UI/user-visible deception risk`
- `local-only`
- `unstable lifecycle`
- `requires mutating RPC`
- `unknown ownership`
- `destructive metadata loss`
- `stale-state overwrite risk`
- `crash-suspect`
- `diagnostic-only`
- `unsupported`

## 3. Unsafe Path Table Schema

| Path ID | Category | Object/Class | Function/Property/Event | Unsafe reason | Evidence basis | Current status | Can be re-reviewed? | Re-review prerequisites | Notes |
|---|---|---|---|---|---|---|---|---|---|
| placeholder-none | none | none | none | unsupported | no current evidence | unsupported | no | none | No write path is safe today. |

## 4. Pre-Seeded Unsafe Or Blocked Entries

| Path ID | Category | Object/Class | Function/Property/Event | Unsafe reason | Evidence basis | Current status | Can be re-reviewed? | Re-review prerequisites | Notes |
|---|---|---|---|---|---|---|---|---|---|
| unsafe-raw-live-inventory-array-rebuild | Inventory items | unknown | raw live inventory array rebuilds | destructive metadata loss; inventory authority; save-persistent | Safe write-path policy. | unsafe | yes | Full item identity, `InventoryInfo`, `Enhancements`, duplicate semantics, UI/OnRep, persistence, rollback, lifecycle proof. | Normal read access does not approve rebuilds. |
| unsafe-raw-inventoryinfo | Inventory metadata | unknown | raw writes to `InventoryInfo` | inventory authority; save-persistent | Safe write-path policy. | unsafe | yes | Metadata proof plus official path failure and sandbox approval. | Blocked. |
| unsafe-raw-enhancements | Enhancements | unknown | raw writes to `Enhancements` | inventory authority; destructive metadata loss | Safe write-path policy. | unsafe | yes | Enhancement shape/value proof plus official path failure and sandbox approval. | Blocked. |
| unsafe-raw-level-accumulatedbuff | Inventory metadata | unknown | raw writes to `Level`/`AccumulatedBuff` | inventory authority; save-persistent | Safe write-path policy. | unsafe | yes | Scalar metadata proof, clamp proof, persistence/rollback proof. | Blocked. |
| unsafe-raw-keys | Resources | unknown | raw writes to Keys | gameplay-authoritative; currency/progression | Resource safety policy. | unsafe | yes | Explicit keys policy and official path proof. | Blocked. |
| unsafe-raw-unlocks-save | Save/persistence | unknown | raw writes to unlock/progression/save data | save-persistent; currency/progression | Safety policy. | unsafe | no | Explicit user re-approval and separate save-safety research. | Blocked. |
| unsafe-unscoped-crabhc-writes | Health | `CrabHC` | unscoped `CrabHC` writes | health/gameplay-critical; unknown ownership | Known ambiguity around unscoped `FindFirstOf(CrabHC)`. | unsafe | yes | Player-owned health component proof plus sandbox approval. | Do not use unscoped `CrabHC`. |
| unsafe-unknown-role-writes | Lifecycle | any | writes from unknown role | unknown ownership; stale-state overwrite risk | Lifecycle safety policy. | unsafe | no | Stable role gate evidence. | Blocked. |
| unsafe-unstable-lifecycle-writes | Lifecycle | any | writes during startup/loading/travel/respawn/join/disconnect | unstable lifecycle; stale-state overwrite risk | Lifecycle safety policy. | unsafe | no | Stable lifecycle window proof. | Blocked. |
| unsafe-unstable-rpc-calls | RPCs/Writes | any | mutating RPC calls during unstable lifecycle | requires mutating RPC; unstable lifecycle | Safe write-path policy. | unsafe | no | Stable lifecycle and explicit sandbox approval. | RuntimeProbe must not call mutating RPCs. |
| unsafe-identity-writes | Identity/session | `PlayerState`/identity surfaces | identity/matchmaking/display-name writes | identity/matchmaking; UI/user-visible deception risk | Identity safety policy. | unsafe | yes | Explicit review and privacy policy; default remains blocked. | Raw identity remains redacted by default. |
| unsafe-gameplay-fields-carrier | P2P carrier | gameplay fields | gameplay-critical fields as `CrabSyncBlock` carriers | gameplay-authoritative | Carrier safety policy. | unsafe | yes | Carrier readiness reclassification plus explicit approval. | Read visibility does not approve payload use. |
| unsafe-crystals-carrier | P2P carrier | resource state | `Crystals` as custom payload carrier | currency/progression; gameplay-authoritative | Carrier unsafe paths. | unsafe | yes | Explicit reclassification and proof, currently out of scope. | Never use crystals as carrier by default. |
| unsafe-healthinfo-carrier | P2P carrier | `HealthInfo` | `HealthInfo` as custom payload carrier | health/gameplay-critical | Carrier unsafe paths. | unsafe | yes | Explicit reclassification and proof, currently out of scope. | Health visibility can support derivation only. |
| unsafe-equipment-da-carrier | P2P carrier | equipment DA fields | equipment DA fields as custom payload carrier | equipment authority | Carrier unsafe paths. | unsafe | yes | Explicit reclassification and proof, currently out of scope. | Equipment DA visibility is not carrier approval. |
| unsafe-slots-carrier | P2P carrier | slot fields | `Num*Slots` as custom payload carrier | gameplay-authoritative | Carrier unsafe paths. | unsafe | yes | Explicit reclassification and proof, currently out of scope. | Slot visibility is not carrier approval. |
| unsafe-inventory-arrays-carrier | P2P carrier | inventory arrays | live inventory arrays as custom payload carrier | inventory authority; save-persistent | Carrier unsafe paths. | unsafe | yes | Explicit reclassification and proof, currently out of scope. | Inventory arrays are not payload channels. |

These entries do not mean normal read access is unsafe. They mean write/use-as-carrier is unsafe or blocked unless future evidence and explicit approval reclassify it.
