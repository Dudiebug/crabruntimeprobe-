# Write Path Sandbox Smoke Plan

This is a future-only manual sandbox plan for the smallest possible CrabSyncV2 write-smoke tests. It is not RuntimeProbe, is not authorized today, and requires explicit user approval before implementation.

Passing smoke only creates an experimental candidate, not production safety.

## 1. Purpose

The purpose of this template is to define what must be documented before a future CrabSyncV2-only write-smoke can be proposed and how the result should be recorded.

## 2. Minimum Prerequisites

- Path exists in [Write Path Ledger](WRITE_PATH_LEDGER.md).
- Path is not listed as unsafe in [Write Path Unsafe Paths](WRITE_PATH_UNSAFE_PATHS.md).
- Natural call/before-after evidence exists where applicable.
- Arguments are understood.
- Authority is understood.
- Lifecycle window is understood.
- Side effects are understood.
- Persistence behavior is understood or explicitly bounded.
- UI/OnRep follow-up is understood.
- Rollback/clear theory exists.
- Disposable test run is defined.
- Explicit user approval is documented.
- One path at a time.
- One tiny/no-op or naturally equivalent state change.

These prerequisites do not authorize the test.

## 3. Sandbox Smoke Table Schema

| Path ID | Approval date | Test owner | Test role | Context | Lifecycle state | Target object/class | Function/property/event | Test value or action | Expected effect | Expected non-effects | Clear/reset method | Pre-state captured | Post-state captured | UI/OnRep observed | Persistence checked | Result | Abort reason | Evidence session | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| none | none | none | none | none | none | none | none | none | none | none | none | no | no | no | no | not_run | none | none | No write-smoke is authorized today. |

## 4. Abort Criteria

- Crash.
- Dirty save risk.
- Identity/name/session changed.
- Gameplay value changed unexpectedly.
- Value persists unexpectedly.
- Remote mismatch.
- Lifecycle instability.
- UI deception.
- Unknown side effect.
- Host/joined authority mismatch.
- Stale-state overwrite.
- Metadata loss.

## 5. Result Meanings

- `not_run`: no test was run.
- `aborted`: test stopped due to abort criteria.
- `failed`: expected behavior did not occur or unsafe behavior was observed.
- `passed_once`: one approved sandbox smoke passed.
- `repeated_clean`: repeated approved runs were clean.
- `experimental_candidate`: candidate may be discussed as limited experimental capability.
- `rejected`: candidate is no longer viable.
- `needs_more_evidence`: more passive or sandbox evidence is required.

## 6. Production Boundary

- Passing once is not production safety.
- Requires repeated clean passes.
- Requires join/travel/respawn coverage.
- Requires role coverage.
- Requires no crash/dirty state.
- Requires final human review.
- Requires capability gate in CrabModFramework/CrabSyncV2.
