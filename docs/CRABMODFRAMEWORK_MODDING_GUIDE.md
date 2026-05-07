# CrabModFramework Modding Guide

This is future architecture and mod-author guidance. CrabModFramework does not exist as runtime code today, and this document does not implement APIs, authorize RuntimeProbe writes, call RPCs, or require local UE4SS runtime work.

## 1. Purpose

CrabModFramework is the planned safe modding layer for Crab Champions mods. It should be built from RuntimeProbe evidence so future mods can use reviewed wrappers instead of raw UE4SS paths.

Mods should prefer CrabModFramework wrappers for context, PlayerState, equipment, resources, health, inventory reads, DataAsset catalogs, P2P helpers, events, and diagnostics. Raw UE4SS calls should be treated as exceptional and eventually linted.

Framework APIs are evidence-gated. A wrapper can exist only when the related capability has a documented status and clear behavior for success, unsupported, unsafe, stale, and crash-suspect outcomes.

Unsupported is a valid safe result. A mod should skip or degrade gracefully when a capability is unsupported rather than widening into unsafe access.

## 2. Evidence-Backed Access Model

- Objectdump presence is not runtime safety.
- RuntimeProbe evidence determines capability status.
- Read safety is not write safety.
- Transport safety is not write/apply safety.
- Function presence is not call safety.
- Natural observation is not automatic permission to mimic.

Evidence-backed access means a specific path worked under a specific context, role, lifecycle state, gate set, and evidence session. It does not prove adjacent paths, deeper traversal, mutation, or other roles.

## 3. Recommended Mod Structure

A future CrabModFramework-based mod can use this shape:

- `main.lua`: minimal entrypoint that loads modules and registers lifecycle-safe work.
- `config.txt`: explicit feature gates and experimental capability toggles.
- `modules/context.lua`: role, lifecycle, generation, and stability checks.
- `modules/readers.lua`: wrapper calls only; no raw UE4SS traversal.
- `modules/state.lua`: normalized local mod state and unsupported markers.
- `modules/policies.lua`: merge/display/skip decisions that never invent evidence.
- `modules/diagnostics.lua`: structured logs for capability results and skip reasons.
- `modules/experimental_write.lua`: disabled by default; future-only and capability-gated.

This is a recommendation, not an implementation requirement.

## 4. Safe Result Model

| Status | Meaning | Consuming Mod Behavior | May Apply State? | Log/Skip |
|---|---|---|---|---|
| `ok` | Wrapper returned a value under an allowed capability. | Use value within documented scope. | Only if a separate apply capability exists. | Log source proof at normal diagnostic level. |
| `nil` | Runtime path safely returned nil. | Treat value as absent, not failed. | No. | Log if absence changes behavior. |
| `unsupported` | Capability/path is not proven or cleanly unavailable. | Skip feature or omit category. | No. | Log unsupported reason. |
| `unsafe` | Capability/path is forbidden or evidence marks it unsafe. | Stop that feature path. | No. | Log unsafe reason prominently. |
| `crash-suspect` | Evidence or runtime state may be associated with instability. | Suspend deeper behavior. | No. | Log crash-suspect reason and require review. |
| `stale` | Source object, generation, lifecycle, or role is no longer trustworthy. | Discard value and wait for stable generation. | No. | Log stale reason when useful. |
| `diagnostic-only` | Value is useful for observation but not readiness promotion. | Display/log only. | No. | Log as diagnostic. |
| `objectdump-only` | Static symbol exists but runtime safety is unproven. | Do not call; plan research only. | No. | Log as blocked if requested. |
| `runtime-confirmed-local` | Runtime evidence confirms local read under scoped conditions. | Use locally within role/lifecycle gates. | No by default. | Log source proof. |
| `runtime-confirmed-remote` | Runtime evidence confirms remote/visible read under scoped conditions. | Use for read-only convergence/display within gates. | No by default. | Log source proof and visibility class. |
| `experimental` | Future manually approved capability with limited evidence. | Use only behind explicit feature gate. | Only if the experimental write gate says so. | Log every use and skip. |
| `unavailable` | Capability is not exposed by the framework. | Feature remains disabled. | No. | Log missing capability if requested. |

Read result statuses never authorize writes by themselves.

## 5. Lifecycle And Role Gates

Do not read risky paths or apply state during startup, loading, travel, respawn, join, disconnect, or unstable local player state unless the specific capability explicitly allows that lifecycle.

Require stable PlayerState and stable generation before trusting state.

Joined clients default to read-only and no-apply.

Unknown role means no risky reads and no writes.

`crash-suspect` means suspend deeper behavior and require review before promotion.

## 6. Diagnostics Expectations

Mods should log:

- Capability requested.
- Capability status.
- Source proof.
- Lifecycle state.
- Role.
- Skip reason.
- Unsupported reason.
- Unsafe reason.
- Crash-suspect reason.
- Planned write/apply skipped reason.

Diagnostics should be structured enough to trace a value back to evidence status without exposing raw private identity.

## 7. How To Request New Capabilities

1. Add or extend a RuntimeProbe evidence plan.
2. Run read-only proof first.
3. Generate docs and evidence summaries.
4. Update the capability model.
5. Only then expose a framework wrapper.

Writes require separate safe write-path discovery, passive observation, explicit user approval, and future CrabSyncV2-only sandbox proof. RuntimeProbe remains read-only.

## 8. What Not To Do

- Do not use raw array traversal outside wrappers.
- Do not access `InventoryInfo` directly before proof.
- Do not access `Enhancements` directly before proof.
- Do not write fields or call RPCs outside capability gates.
- Do not use unscoped `FindFirstOf(CrabHC)` for player health.
- Do not hijack gameplay fields as payload carriers.
- Do not leak raw identity values.
- Do not mutate save, progression, currency, keys, unlocks, or account-like state.
- Do not perform broad recursive object crawling.
- Do not treat unknown metadata as default metadata.
- Do not use P2P carrier readiness as write/apply readiness.

## 9. Example Mod Behavior

Read equipment safely: a mod asks the Equipment wrapper for local and visible equipment. If the capability returns `runtime-confirmed-local` or `runtime-confirmed-remote`, the mod displays the DA identity with source proof. It does not call equipment setters.

Read health snapshot safely: a mod asks the Health wrapper for a PlayerState-scoped health snapshot. If lifecycle is stable, it can display current/max values. It does not write `HealthInfo` or infer pooled health apply safety.

Receive unsupported inventory metadata: a mod asks for `InventoryInfo` before the proof phase exists. The wrapper returns `unsupported`, and the mod skips item sync rather than defaulting `Level`, `AccumulatedBuff`, or `Enhancements`.

Detect carrier unavailable: a P2P feature asks for carrier read support. If the capability returns `unavailable`, P2P transport remains disabled and visible-state derivation is used only where independently proven.

Skip write/apply: a mod builds a proposed state change but the write path is not proven. Diagnostics record that apply was skipped because write-path capability is unavailable.
