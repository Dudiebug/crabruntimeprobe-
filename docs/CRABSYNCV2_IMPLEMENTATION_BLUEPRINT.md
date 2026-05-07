# CrabSyncV2 Implementation Blueprint

This is a future architecture plan, not an implementation request. RuntimeProbe remains a read-only evidence collector.

## High-Level Modules

- Lifecycle detector: detects startup, menu, lobby, loading, travel, respawn, join, disconnect, role changes, and local player stability.
- Safe local reader: reads only currently proven local PlayerState paths.
- Visible peer-state reader: samples only evidence-proven replicated data from local and remote PlayerStates.
- Evidence-gated inventory reader: progresses from shape to count to wrapper to element to metadata only when evidence permits.
- Health reader: starts at `CrabPC -> PlayerState -> CrabPS -> HealthInfo` and follows the read-only [CrabSyncV2 Health P2P Model](CRABSYNCV2_HEALTH_P2P_MODEL.md).
- Resource reader: reads crystals, slots, equipment, and other scalar resources only from proven paths and follows the read-only [CrabSyncV2 Resource P2P Model](CRABSYNCV2_RESOURCE_P2P_MODEL.md).
- Identity/session mapper: maps local/remote players using fingerprinted identity and session context.
- P2P merge engine: combines game-native peer-visible state using role/generation/timestamp guards and without blind stale overwrites; health/resource merge planning uses the health and resource P2P models as convergence specs, not apply approval.
- Deterministic convergence planner: computes category-specific reconciliation math where peer visibility is sufficient.
- P2P carrier layer (provisional, disabled): future module that may read/write `CrabSyncBlock` only through a proven safe replicated carrier.
- Apply planner: computes a plan before any write and marks skips with reasons; health/resource read convergence from the P2P models never makes apply safe by itself.
- Apply executor: future gated write/RPC layer, separate from RuntimeProbe, and blocked until [CrabSyncV2 Safe Write Path Discovery](CRABSYNCV2_SAFE_WRITE_PATH_DISCOVERY.md) evidence, [Write Path Ledger](WRITE_PATH_LEDGER.md) status, and sandbox criteria exist.
- Rollback/skip safety layer: aborts applies on instability and keeps local state safe.
- Diagnostics/evidence logger: records reads, planned writes, skipped applies, and safety gate reasons.

## Proposed State Machine

- `disabled`: no reads or writes.
- `startup_warmup`: wait for UE4SS/game startup to settle.
- `probing`: evidence collection or confidence checks.
- `local_read_only`: local reads allowed, no apply.
- `peer_visible_read_only`: replicated peer-visible data collection, no apply.
- `host_read_write_candidate`: host appears stable, but write eligibility still gated.
- `joined_read_only`: joined client reads only; no apply by default.
- `stable`: all required gates stable for the current role and feature set.
- `suspended`: lifecycle transition or uncertainty detected; skip reads/applies.
- `crash_suspect`: stop deeper work and require manual review.

## Deterministic Peer-State Model

Each snapshot row should include:

- Visible player snapshot ID.
- Generation and timestamp.
- Source role (`host`, `joined`, `solo`, `unknown`).
- Local/remote visibility class (`local_only`, `peer_visible`, `host_only_candidate`, `unresolved`).
- Category payload (`health`, `equipment`, `crystals`, `slots`, `inventory`).
- Unsupported-field markers for fields that are missing, unresolved, or unsafe.
- Evidence confidence (`objectdump_only`, `runtime_safe_local`, `runtime_safe_joined`, `runtime_safe_remote_visible`, `unresolved`, `unsafe`).

## Proposed Data Model

- Player identity fingerprint.
- Equipment: weapon, ability, melee DA identity.
- Resources: crystals and explicitly scoped scalar resources; keys may be visible but are excluded unless explicitly re-approved.
- Slots: weapon/ability/melee/perk slot scalars.
- Health snapshot: current, max, base max, multiplier, source path, timestamp.
- Inventory items with full metadata: DA short name, preferred full DA identity/path, `Level`, `AccumulatedBuff`, `Enhancements`, category, index, and source proof.
- Generation/cycle counters for read generations and apply generations.
- Source role: host, joined client, solo, unknown.
- Visibility class and unsupported-field markers.
- Evidence confidence labels.

## Apply Policy

- Plan before write.
- Compare full normalized state, not display names only.
- Do not perform destructive rebuilds without proven metadata preservation.
- Skip on lifecycle, role, PlayerState, generation, inventory, or evidence instability.
- Log every skipped apply with a reason.

## P2P Merge Policy

- Prefer game-native replicated observations over external transport state.
- Clamp values to objectdump-backed property ranges.
- Preserve item metadata.
- Do not blindly overwrite safer local runtime state with stale peer state.
- Separate local-only, shared, host-authoritative-candidate, and unresolved fields.
- Use generation/timestamp/role-aware merge policy over blind last-write-wins.
- Health convergence policy is detailed in [CrabSyncV2 Health P2P Model](CRABSYNCV2_HEALTH_P2P_MODEL.md).
- Resource/equipment convergence policy is detailed in [CrabSyncV2 Resource P2P Model](CRABSYNCV2_RESOURCE_P2P_MODEL.md).

## No Transport Until Proven

- No relay/server/bridge/JSON IPC transport is part of CrabSyncV2 baseline planning.
- `CrabSyncBlock` carrier behavior stays disabled until dedicated carrier-discovery/read evidence exists.
- Any eventual carrier write-smoke work is future, explicitly gated, and outside RuntimeProbe default behavior.

## Migration Policy

CrabInvSync v1 behavior should not be copied blindly. Every v1 behavior must be mapped to proven RuntimeProbe evidence, objectdump facts plus a marked assumption, or a legacy risky bucket that stays disabled until research catches up.

Use [CrabSyncV2 v1 Migration Doctrine](CRABSYNCV2_V1_MIGRATION_DOCTRINE.md) before reusing any v1 behavior. v1 is archival/prototype reference only; bridge/server/relay/JSON IPC behavior is not a v2 foundation.
