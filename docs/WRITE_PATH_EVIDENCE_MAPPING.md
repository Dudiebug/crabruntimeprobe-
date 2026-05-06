# Write Path Evidence Mapping

This document defines how future passive RuntimeProbe evidence rows should map into write-path planning and status documents. It is a mapping specification only. It does not implement collectors, hooks, gates, probes, Lua code, imports, write behavior, RPC calls, or write-smoke tests.

RuntimeProbe remains read-only. Mapping evidence into a ledger or status document does not approve a write, does not authorize a mutating RPC, and does not make CrabSyncV2 apply-ready. Read evidence, function presence, natural observation, sandbox evidence, and write safety are separate evidence classes.

## 1. Purpose

The purpose of this mapping is to keep future write-path planning evidence consistent across:

- [Write Path Ledger](WRITE_PATH_LEDGER.md)
- [Write Path Unsafe Paths](WRITE_PATH_UNSAFE_PATHS.md)
- [Write Path Observed Natural Calls](WRITE_PATH_OBSERVED_NATURAL_CALLS.md)
- [Write Path Sandbox Smoke Plan](WRITE_PATH_SANDBOX_SMOKE_PLAN.md)

Future passive observation may show that Crab Champions naturally calls a function, changes a property, triggers an event, refreshes UI, or persists state. That observation is evidence for planning only. It is not permission for RuntimeProbe or CrabSyncV2 to mimic the behavior. Function presence is not call safety. Natural game behavior is not automatic mimic safety. Raw read visibility is not write safety.

## 2. Source Evidence Row Families

These evidence kinds are planned future row families. They are not currently implemented by this task and do not imply existing evidence rows.

| Evidence kind | Planned meaning |
|---|---|
| `WritePath.FunctionPresence.Candidate` | A function, property, event, or OnRep name is known from static or passive runtime identification without calling it. |
| `WritePath.NaturalCall.Observed` | Vanilla gameplay appears to invoke a function, RPC, event, OnRep, UI refresh, or property change naturally. |
| `WritePath.BeforeAfter.Sample` | Passive read-only pre/post state around a natural change was captured. |
| `WritePath.Authority.Observed` | Passive observation records owner/source, local role, remote role, direction, or authority context. |
| `WritePath.Lifecycle.Sample` | Passive observation records timing relative to stable play, join, travel, respawn, loading, disconnect, or other lifecycle states. |
| `WritePath.OnRepOrUIFollowup.Observed` | Passive observation records naturally occurring replication/UI follow-up after a natural change. |
| `WritePath.Persistence.Observed` | Passive observation records whether natural behavior appears transient, session-scoped, save-persistent, or unknown. |
| `WritePath.Rejection` | Evidence or review marks a path unsafe, unsupported, crash-suspect, diagnostic-only, or blocked. |
| `WritePath.Safety.Marker` | A row records safety flags for the observation phase. |
| `WritePath.Summary` | A future generated summary aggregates status without inventing proof. |

Expected fields for future rows:

| Field | Expected use |
|---|---|
| `sessionId` | Stable evidence session identifier. |
| `timestamp` | Observation timestamp. |
| `phaseId` | Future passive observation phase identifier. |
| `localRole` | Local runtime role, or `unknown`. |
| `remoteRole` | Remote peer role when relevant, or `unknown`. |
| `context` | Solo, host, joined client, menu, lobby, run, transition, or other observed context. |
| `lifecycleState` | Stable play, startup, loading, join, travel, respawn, disconnect, teardown, or `unknown`. |
| `objectClass` | Normalized class name when safe to emit. |
| `objectFullName` or redacted object identity | Full object identity only if approved; otherwise a redacted stable label. |
| `functionOrPropertyOrEventName` | Function, RPC, property, OnRep, UI refresh, event, or candidate name. |
| `pathCategory` | Normalized category such as equipment, inventory, inventory metadata, enhancements, slots, crystals, health, armor, UI refresh, carrier, save/persistence, identity/session, lifecycle, or unknown. |
| `pathType` | Normalized path type from the ledger mapping rules. |
| `ownerSource` | Observed owner/source object or redacted identity. |
| `callerSource` | Natural caller/source when passively observed, or `unknown`. |
| `direction` | Local, host-to-client, client-to-host, replicated, UI-only, persistence, unknown, or not-applicable. |
| `authorityObserved` | Observed authority status; never inferred as safe without evidence. |
| `argsObserved` | Whether arguments were passively observed. |
| `argsRedacted` | Whether private/raw values were redacted. |
| `preStateCaptured` | Whether pre-state was passively captured. |
| `postStateCaptured` | Whether post-state was passively captured. |
| `onRepObserved` | Whether OnRep follow-up was naturally observed. |
| `uiFollowupObserved` | Whether UI follow-up was naturally observed. |
| `persistenceObserved` | Whether persistence behavior was naturally observed. |
| `rawPrivateValuesEmitted` | Must default to false unless explicitly approved. |
| `result` | Observed, rejected, unsupported, dirty, crash-suspect, summary, or not-applicable. |
| `rejectionReason` | Reason when rejected, unsafe, unsupported, crash-suspect, or diagnostic-only. |
| `crashSuspicion` | Whether the row is associated with suspected crash/native instability. |
| `dirtyEvidence` | Whether the row is incomplete, conflicting, stale, contaminated, or otherwise dirty. |
| `safetyMarkers` | Required marker set for passive observation phases. |
| `notes` | Short planning note without implying approval. |

## 3. Mapping To Write Path Ledger

Future rows may create or update a row in [Write Path Ledger](WRITE_PATH_LEDGER.md) only as planning/status data.

### Ledger Row Rules

- Path ID generation: use stable lowercase kebab-case from normalized category, path type, and function/property/event name, for example `equipment-rpc-server-equip-inventory`. Use `raw-` prefixes for raw write candidates and `carrier-` prefixes for carrier write-smoke candidates. Do not encode session IDs into path IDs.
- Category normalization: map evidence categories to ledger sections. Unknown categories stay `unknown` until reviewed.
- Object/Class normalization: prefer class name over raw object identity. Use redacted object labels when private, unstable, or overly specific identities would leak information.
- Function/Property/Event naming: preserve the exact symbol name when known, wrapped in code formatting in docs. Use descriptive names such as `raw inventory array rebuild` only for non-symbol raw write families.
- Path type classification: normalize to one of `function`, `RPC`, `property`, `event`, `OnRep`, `UI refresh`, `raw write candidate`, or `carrier write-smoke candidate`. Raw write candidate means blocked or future last-resort planning, not approval.
- Observed naturally mapping: set yes only from `WritePath.NaturalCall.Observed`, passive property-change samples, natural OnRep/UI observations, or reviewed equivalent passive evidence.
- Args understood mapping: set yes only when arguments are passively observed, redacted as needed, and reviewed enough to describe shape and constraints. Presence of an argument list is not enough.
- Authority mapping: use `WritePath.Authority.Observed` rows. Unknown authority blocks promotion.
- Direction mapping: use observed direction only; do not infer client-to-host or host-to-client safety from function names alone.
- Local/remote role mapping: preserve observed local and remote roles. Role ambiguity must be explicit.
- Lifecycle window mapping: use `WritePath.Lifecycle.Sample`; unstable or transition-state evidence must not promote readiness.
- Pre-state/Post-state captured mapping: set independently from passive before/after evidence. Missing pre-state or post-state keeps before/after incomplete.
- UI/OnRep observed mapping: set only when naturally observed; OnRep presence does not authorize calling OnRep manually.
- Persistence behavior mapping: record transient, session-scoped, save-persistent, not-observed, or unknown. Unknown persistence blocks smoke proposal except when explicitly bounded by review.
- Side effects mapping: summarize observed side effects and suspected non-effects. Unknown side effects remain unknown.
- Current status mapping: follow the transition rules below. Do not skip evidence levels because a symbol looks plausible.
- Risk level mapping: use conservative `critical`, `high`, `medium`, `low`, or `unknown`. Gameplay-authoritative, save-persistent, identity, currency/progression, inventory authority, equipment authority, health/gameplay-critical, mutating RPC, raw write, and carrier candidates default to high or critical until reviewed.
- Evidence session reference: include session IDs or evidence bundle references without embedding private values.
- Next evidence needed: state the next missing evidence class, not an implementation step.

### Status Transition Rules

Allowed planning transitions:

- `objectdump-only` -> `function-presence-confirmed`
- `function-presence-confirmed` -> `naturally-observed-call`
- `naturally-observed-call` -> `naturally-observed-before-after`
- `naturally-observed-before-after` -> `naturally-observed-authority`
- `naturally-observed-authority` -> `naturally-observed-lifecycle-window`
- `naturally-observed-lifecycle-window` -> `candidate-write-path`
- `candidate-write-path` -> `sandbox-write-smoke-proposed`, only after human review
- `sandbox-write-smoke-proposed` -> `sandbox-write-smoke-passed`, only after future CrabSyncV2-only sandbox evidence
- any status -> `unsafe`
- any status -> `unsupported`
- any status -> `crash-suspect`
- any status -> `diagnostic-only`

No automated mapping may promote a path to `sandbox-write-smoke-proposed`. No RuntimeProbe evidence may promote a path to `sandbox-write-smoke-passed`. `production-safe-gated` requires repeated future evidence, role/lifecycle coverage, rollback or clear proof, explicit review, and capability gates. No path is production-safe today.

## 4. Mapping To Observed Natural Calls

[Write Path Observed Natural Calls](WRITE_PATH_OBSERVED_NATURAL_CALLS.md) records passive samples of natural game behavior. It is not a call approval list.

- Use one row per observed call, event, OnRep, UI refresh, or property-change sample.
- Group related observations by session and category.
- Preserve role, context, lifecycle state, owner/source, caller/source, direction, and authority information.
- Record arguments only under the redaction policy. Redact raw identity, private values, unstable object identities, and sensitive payload-like values by default.
- Record before/after only when passively observed. Do not synthesize pre-state or post-state.
- Record UI/OnRep follow-up only when naturally observed.
- Record persistence only when naturally observed or explicitly bounded as not observed.
- Mark dirty or crash-suspect evidence explicitly and prevent readiness promotion from that row.

Handling rules:

- Repeated natural calls: keep separate sample rows when context, arguments, roles, lifecycle, or result differ. Summaries may aggregate counts but must not erase variation.
- Conflicting observations: mark unresolved or dirty and preserve both sides until reviewed.
- Partial observations: record the observed subset and mark missing fields unknown.
- Role ambiguity: keep localRole, remoteRole, direction, and authority as unknown or ambiguous; do not infer safety.
- Missing pre-state: do not set before/after confidence.
- Missing post-state: do not set before/after confidence.
- Transition-state observations: tag lifecycle state clearly and block promotion unless the transition itself is the reviewed target.
- Raw/private value redaction: default to redacted. Raw private values require explicit approval and must be marked in the row.

## 5. Mapping To Unsafe Paths

[Write Path Unsafe Paths](WRITE_PATH_UNSAFE_PATHS.md) records rejected, blocked, or unresolved write/apply paths so read evidence and function presence are not mistaken for apply readiness.

Rejection rules:

- Gameplay-authoritative and not safely bounded -> `unsafe`.
- Currency/progression -> `unsafe`.
- Identity, matchmaking, or display identity -> `unsafe`.
- Save-persistent with unknown clear/reset -> `unsafe`.
- Health/gameplay critical -> unsafe as a custom carrier and unsafe to write unless future health apply evidence exists.
- Equipment authority -> unsafe until official path proof exists.
- Inventory authority -> unsafe until full metadata and apply proof exists.
- UI/user-visible deception risk -> unsafe unless explicitly reviewed.
- Local-only -> unusable for remote sync.
- Unstable lifecycle -> unsafe or unresolved.
- Requires mutating RPC -> blocked in RuntimeProbe.
- Unknown ownership -> unresolved or unsafe pending review.
- Destructive metadata loss -> unsafe.
- Stale-state overwrite risk -> unsafe.
- Crash-suspect -> blocks promotion.

A path can be safe to read but unsafe to write. A path can be useful for P2P derivation but unsafe for mutation. Unsafe write status does not erase confirmed safe read evidence. RuntimeProbe cannot turn an unsafe write path into a safe write path because RuntimeProbe does not perform writes.

## 6. Mapping To Sandbox Smoke Plan

[Write Path Sandbox Smoke Plan](WRITE_PATH_SANDBOX_SMOKE_PLAN.md) is future-only and CrabSyncV2-only. RuntimeProbe must not implement or run write-smoke.

Evidence required before a future write-smoke row can even be proposed:

- Path exists in [Write Path Ledger](WRITE_PATH_LEDGER.md).
- Path is not in [Write Path Unsafe Paths](WRITE_PATH_UNSAFE_PATHS.md).
- Natural call observation exists when applicable.
- Before/after evidence exists when applicable.
- Arguments are understood.
- Authority is understood.
- Lifecycle window is understood.
- Persistence behavior is understood or explicitly bounded.
- UI/OnRep follow-up is understood or explicitly not required.
- Rollback/clear theory exists.
- Explicit user approval is still required.
- CrabSyncV2-only sandbox is required.
- RuntimeProbe does not implement or run write-smoke.

A write-smoke proposal is a human-reviewed decision, not automatic mapping. Passing once creates only an experimental candidate. Repeated clean evidence is required before any production capability discussion.

## 7. Evidence Confidence Levels

| Confidence level | Meaning |
|---|---|
| `objectdump-only` | Static/objectdump symbol or candidate only. No runtime call proof. |
| `function-presence-observed` | Passive runtime identification without calling. |
| `natural-call-observed` | Vanilla behavior appears to invoke or trigger a path naturally. |
| `before-after-observed` | Passive pre/post state was captured around natural behavior. |
| `authority-observed` | Owner, role, authority, or direction was passively observed. |
| `lifecycle-observed` | Lifecycle window was passively observed. |
| `ui-followup-observed` | UI or OnRep follow-up was passively observed. |
| `persistence-observed` | Persistence behavior was passively observed or explicitly bounded. |
| `rejected` | Review or evidence rejects the path. |
| `unsupported` | Evidence cannot support planning for the path. |
| `crash-suspect` | Crash or native instability suspicion blocks promotion. |
| `diagnostic-only` | Useful as diagnostic context only. |
| `experimental-write-candidate` | Future only; requires approved sandbox evidence and still is not production-safe. |
| `production-gated` | Future only; requires repeated evidence, explicit review, rollback/clear proof, and capability gates. |

## 8. Required Safety Markers

Future passive write-path observation phases must include these safety markers:

- `noWrites = true`
- `noRpcs = true`, unless the row is only observing a naturally occurring RPC and does not call it
- `noMutation = true`
- `noSyntheticPayloads = true`
- `noDataAssetMutation = true`
- `noInventoryInfo` unless explicitly part of a separate read-proof phase
- `noEnhancements` unless explicitly part of a separate read-proof phase
- `rawIdentityEvidence = false` unless explicitly approved
- `passiveOnly = true`
- `noFunctionCallsByProbe = true`
- `noForcedGameplayState = true`

Rows missing these markers are dirty for readiness purposes until reviewed.

## 9. Example Placeholder Mappings

These examples are fictional non-evidence examples. They do not record new evidence and do not approve writes.

| Non-evidence example | Mapping result |
|---|---|
| `ServerEquipInventory` function presence | Maps to `objectdump-only` or `function-presence-confirmed`. It is not callable from RuntimeProbe and is not mimic-safe. |
| Natural pickup flow | Maps to `naturally-observed-call` if passively observed. It still does not prove arguments, authority, lifecycle, persistence, or mimic safety. |
| Inventory array raw rebuild | Maps to `unsafe` due to destructive metadata loss unless future full metadata preservation and official path failure proof exists. It is not preferred. |
| `HealthInfo.CurrentHealth` read visibility | Useful for P2P derivation planning, but not write safety and not a custom carrier approval. |
| `OnRep_Inventory` natural observation | Maps to UI/replication follow-up evidence. It is not permission to call `OnRep_Inventory`. |
| `ClientRefreshPSUI` presence | Maps to `function-presence-confirmed` at most. Presence is not permission to call it. |

## 10. Relationship To Existing Docs

- [CrabSyncV2 Safe Write Path Discovery](CRABSYNCV2_SAFE_WRITE_PATH_DISCOVERY.md) defines the passive-first methodology. This mapping defines where future passive rows land.
- [Write Path Ledger](WRITE_PATH_LEDGER.md) receives normalized candidate/status rows from future evidence.
- [Write Path Unsafe Paths](WRITE_PATH_UNSAFE_PATHS.md) receives rejected, blocked, unsafe, unsupported, crash-suspect, and diagnostic-only paths.
- [Write Path Observed Natural Calls](WRITE_PATH_OBSERVED_NATURAL_CALLS.md) receives one-row-per-sample passive natural observations.
- [Write Path Sandbox Smoke Plan](WRITE_PATH_SANDBOX_SMOKE_PLAN.md) receives future human-reviewed CrabSyncV2-only sandbox proposals, not automatic imports.
- [CrabSyncV2 Design Rules](CRABSYNCV2_DESIGN_RULES.md) keeps RPC/write constraints separated from read and transport constraints.
- [CrabSyncV2 Research Roadmap](CRABSYNCV2_RESEARCH_ROADMAP.md) treats this mapping as a prerequisite for future write-path import/status tooling.
- [CrabSyncV2 Readiness Checklist](CRABSYNCV2_READINESS_CHECKLIST.md) may later use mapped confidence levels for readiness review. This mapping does not satisfy that checklist by itself.
- CrabModFramework capability modeling may later consume reviewed statuses, but this mapping does not create a capability gate or approve apply behavior.

## 11. Non-Goals

This task and document do not:

- Implement observation hooks.
- Implement import tooling.
- Add RuntimeProbe phases.
- Call RPCs.
- Write properties.
- Test write-smoke.
- Approve writes.
- Declare CrabSyncV2 apply readiness.
