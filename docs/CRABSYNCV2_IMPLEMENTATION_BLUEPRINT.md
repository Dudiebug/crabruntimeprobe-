# CrabSyncV2 Implementation Blueprint

This is a future architecture plan, not an implementation request. RuntimeProbe remains a read-only evidence collector.

## High-Level Modules

- Lifecycle detector: detects startup, menu, lobby, loading, travel, respawn, join, disconnect, role changes, and local player stability.
- Safe local reader: reads only currently proven local PlayerState paths.
- Evidence-gated inventory reader: progresses from shape to count to wrapper to element to metadata only when evidence permits.
- Health reader: starts at `CrabPC -> PlayerState -> CrabPS -> HealthInfo`.
- Resource reader: reads crystals, slots, equipment, and other scalar resources only from proven paths.
- Identity/session mapper: maps local/remote players using fingerprinted identity and session context.
- Merge engine: combines local, remote, and relay/server state without blind stale overwrites.
- Apply planner: computes a plan before any write and marks skips with reasons.
- Apply executor: future gated write/RPC layer, separate from RuntimeProbe.
- Rollback/skip safety layer: aborts applies on instability and keeps local state safe.
- Diagnostics/evidence logger: records reads, planned writes, skipped applies, and safety gate reasons.

## Proposed State Machine

- `disabled`: no reads or writes.
- `startup_warmup`: wait for UE4SS/game startup to settle.
- `probing`: evidence collection or confidence checks.
- `local_read_only`: local reads allowed, no apply.
- `host_read_write_candidate`: host appears stable, but write eligibility still gated.
- `joined_read_only`: joined client reads only; no apply by default.
- `stable`: all required gates stable for the current role and feature set.
- `suspended`: lifecycle transition or uncertainty detected; skip reads/applies.
- `crash_suspect`: stop deeper work and require manual review.

## Proposed Data Model

- Player identity fingerprint.
- Equipment: weapon, ability, melee DA identity.
- Resources: crystals and unresolved resource fields such as keys.
- Slots: weapon/ability/melee/perk slot scalars.
- Health snapshot: current, max, base max, multiplier, source path, timestamp.
- Inventory items with full metadata: DA short name, preferred full DA identity/path, `Level`, `AccumulatedBuff`, `Enhancements`, category, index, and source proof.
- Generation/cycle counters for read generations and apply generations.
- Source role: host, joined client, solo, unknown.
- Evidence confidence: objectdump-only, runtime-safe local, runtime-safe joined, unresolved, unsafe.

## Apply Policy

- Plan before write.
- Compare full normalized state, not display names only.
- Do not perform destructive rebuilds without proven metadata preservation.
- Skip on lifecycle, role, PlayerState, generation, inventory, or evidence instability.
- Log every skipped apply with a reason.

## Merge Policy

- Clamp values to objectdump-backed property ranges.
- Preserve item metadata.
- Do not blindly overwrite safer local runtime state with stale client state.
- Separate local-only, shared, and unresolved fields.

## Migration Policy

CrabInvSync v1 behavior should not be copied blindly. Every v1 behavior must be mapped to proven RuntimeProbe evidence, objectdump facts plus a marked assumption, or a legacy risky bucket that stays disabled until research catches up.
