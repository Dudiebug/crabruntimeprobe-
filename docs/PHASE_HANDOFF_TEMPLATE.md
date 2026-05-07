# Phase Handoff Template

This template is required after every phase. It applies to RuntimeProbe phases, documentation phases, generated docs/import phases, carrier research phases, write-path observation phases, future sandbox phases, and future implementation phases.

Using this template does not authorize writes, RPCs, RuntimeProbe mutation, CrabSyncV2 implementation, or CrabModFramework implementation.

## 1. Purpose

Provide a standard handoff after every phase so the next Codex session or human reviewer can see what changed, what is proven, what is unsupported, and what must not be crossed next.

## 2. Required Handoff Fields

Use these fields for every phase:

| Field | Value |
|---|---|
| Phase ID / task name |  |
| Phase type | documentation / RuntimeProbe read-only evidence / generated docs-import / carrier research / write-path observation / future sandbox / implementation, future only |
| Branch |  |
| Starting commit |  |
| Ending commit |  |
| Push status |  |
| Remote hash |  |
| Files changed |  |
| Commands run |  |
| Validation run |  |
| What changed |  |
| Evidence imported |  |
| Phase result |  |
| Safety markers |  |
| Failures/crash suspicion |  |
| Dirty working tree status |  |
| What is now proven |  |
| What is still not proven |  |
| What remains unsupported |  |
| What was explicitly not done |  |
| Do-not-cross boundaries |  |
| Next recommended phase |  |
| Next Codex prompt summary |  |
| Human/manual run instructions if needed |  |

## 3. Safety Marker Section

Use explicit true/false/unknown values:

| Safety marker | Value | Notes |
|---|---|---|
| `noWrites` |  |  |
| `noRpcs` |  |  |
| `noMutation` |  |  |
| `noHud` |  |  |
| `noDeepArrays` |  |  |
| `noInventoryInfo` |  |  |
| `noEnhancements` |  |  |
| `rawIdentityEvidence` |  |  |
| `noDataAssetMutation` |  |  |
| `passiveOnly` |  |  |
| `crashSuspicion` |  |  |
| `dirtyEvidence` |  |  |

## 4. Result Vocabulary

Common phase results:

- `confirmed`.
- `unsupported`.
- `partial`.
- `failed`.
- `crash-suspect`.
- `diagnostic-only`.
- `blocked`.
- `not-run`.
- `pushed`.
- `push-failed`.
- `merged`.
- `merge-blocked`.

## 5. Documentation-Phase Handoff Example

| Field | Example |
|---|---|
| Phase ID / task name | `docs-add-readiness-checklist` |
| Phase type | documentation |
| Branch | `docs/example-branch` |
| Starting commit | `abc1234` |
| Ending commit | `def5678` |
| Push status | pushed |
| Remote hash | `def5678` |
| Files changed | `docs/EXAMPLE.md`, `docs/README.md` |
| Commands run | `git status --short`, docs validation, `git diff --cached --check` |
| Validation run | docs/evidence docs test passed |
| What changed | Added planning docs and index links |
| Evidence imported | none |
| Phase result | confirmed documentation update |
| Safety markers | `noWrites=true`, `noRpcs=true`, `noMutation=true`, `passiveOnly=true` |
| Failures/crash suspicion | none |
| Dirty working tree status | clean after push |
| What is now proven | documentation exists only |
| What is still not proven | runtime behavior |
| What remains unsupported | selected runtime features |
| What was explicitly not done | no runtime run, no writes/RPCs/code |
| Do-not-cross boundaries | do not treat docs as runtime proof |
| Next recommended phase | next read-only evidence phase |
| Next Codex prompt summary | ask for read-only evidence or follow-up docs |
| Human/manual run instructions if needed | none |

## 6. RuntimeProbe Evidence-Phase Handoff Example

| Field | Example |
|---|---|
| Phase ID / task name | `inventory-element-da-read` |
| Phase type | RuntimeProbe read-only evidence |
| Branch | `docs/example-evidence-branch` |
| Starting commit | `abc1234` |
| Ending commit | `def5678` |
| Push status | pushed |
| Remote hash | `def5678` |
| Files changed | evidence import docs and generated status docs |
| Commands run | prepare command, collect command, import docs command |
| Validation run | generated docs checks and `git diff --cached --check` |
| What changed | imported read-only evidence |
| Evidence imported | session ID and evidence file names |
| Phase result | `confirmed`, `unsupported`, `partial`, or `crash-suspect` |
| Safety markers | full marker table with no writes/RPCs |
| Failures/crash suspicion | crash folder status and diagnostic summary |
| Dirty working tree status | clean or reported dirty files |
| What is now proven | exact scoped read path only |
| What is still not proven | adjacent paths, deeper traversal, writes/apply |
| What remains unsupported | unavailable paths |
| What was explicitly not done | no mutation, no RPCs, no broader traversal |
| Do-not-cross boundaries | do not advance deeper phase without clean proof |
| Next recommended phase | next ladder rung |
| Next Codex prompt summary | summarize safe next task |
| Human/manual run instructions if needed | include exact manual run notes if runtime is required |

## 7. Merge-Phase Handoff Example

| Field | Example |
|---|---|
| Phase ID / task name | `merge-docs-branch` |
| Phase type | generated docs/import or documentation |
| Branch | target branch |
| Starting commit | target/source hashes before merge |
| Ending commit | merge commit |
| Push status | pushed or push-failed |
| Remote hash | verified remote branch hash |
| Files changed | merge result summary |
| Commands run | fetch, status, merge, validation, push |
| Validation run | tests/docs checks |
| What changed | source branch merged into target |
| Evidence imported | none unless stated |
| Phase result | merged or merge-blocked |
| Safety markers | docs-only if applicable |
| Failures/crash suspicion | conflicts or none |
| Dirty working tree status | clean after merge or reported dirty |
| What is now proven | merge completed only |
| What is still not proven | runtime behavior |
| What remains unsupported | unchanged unsupported items |
| What was explicitly not done | no reset, no force push, no runtime run |
| Do-not-cross boundaries | preserve history and unresolved blockers |
| Next recommended phase | next planning/evidence step |
| Next Codex prompt summary | summarize follow-up |
| Human/manual run instructions if needed | conflict notes if any |

## 8. Do-Not-Cross Boundaries

Reusable boundary language:

- Do not move to `InventoryInfo` until item identity proof is clean.
- Do not move to `Enhancements` until `InventoryInfo` scalar proof is clean.
- Do not use carrier until carrier readiness says enough.
- Do not write/apply until safe write-path evidence and sandbox smoke exist.
- Do not start full CrabSyncV2 sync until [CrabSyncV2 Readiness Checklist](CRABSYNCV2_READINESS_CHECKLIST.md) permits the target level.
- Do not treat documentation as runtime proof.
- Do not promote unsupported or crash-suspect evidence into confirmed behavior.
