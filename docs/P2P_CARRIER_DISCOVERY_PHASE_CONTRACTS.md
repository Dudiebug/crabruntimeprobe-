# P2P Carrier Discovery Phase Contracts

This document defines future read-only RuntimeProbe phase contracts for CrabSyncV2 P2P carrier research. These contracts are not implemented phases, do not approve a carrier, and do not authorize writes, RPCs, mutation, synthetic payloads, broad object crawling, or CrabSyncV2 code.

Read-only discovery never equals write safety. Unsupported, rejected, or inconclusive results are valid safe outcomes.

## 1. Purpose

The purpose of these contracts is to define what future RuntimeProbe carrier research phases would be allowed to observe, what evidence rows they should emit, what safety markers they require, and what they must never do.

The contracts support [P2P Carrier Evidence Mapping](P2P_CARRIER_EVIDENCE_MAPPING.md), [P2P Carrier Candidates](P2P_CARRIER_CANDIDATES.md), [P2P Carrier Visibility Matrix](P2P_CARRIER_VISIBILITY_MATRIX.md), and [P2P Carrier Unsafe Paths](P2P_CARRIER_UNSAFE_PATHS.md). They do not prove a carrier exists today.

[P2P Carrier Readiness Checklist](P2P_CARRIER_READINESS_CHECKLIST.md) is the decision layer after future evidence import.

## 2. Phase List

Future carrier research phase contracts:

- `p2p-carrier-discovery-read`
- `p2p-carrier-visibility-watch`
- `p2p-carrier-capacity-read`
- `p2p-carrier-lifecycle-watch`
- `p2p-carrier-rejection-classification`
- `p2p-carrier-summary-import`
- `p2p-carrier-write-smoke`, listed only as out-of-band future CrabSyncV2 sandbox work and not a RuntimeProbe default phase

## 3. `p2p-carrier-discovery-read`

Purpose: discover possible replicated non-gameplay carrier candidates.

Allowed observations:

- Candidate object/class names.
- Candidate field/event/function names.
- Value kind summaries.
- Owner/source summaries.
- Redacted or fingerprinted identity if necessary.
- No raw private values by default.

Forbidden:

- Writes.
- RPCs.
- Mutation.
- DataAsset mutation.
- Inventory traversal.
- `InventoryInfo`.
- `Enhancements`.
- Gameplay field hijacking.
- Broad recursive object crawling.

Required safety markers:

- `noWrites = true`
- `noRpcs = true`
- `noMutation = true`
- `rawIdentityEvidence = false`
- `noDataAssetMutation = true`
- `noInventoryInfo = true`
- `noEnhancements = true`

Expected evidence row families:

- `P2PCarrier.Discovery.Candidate`
- `P2PCarrier.Rejection`
- `P2PCarrier.Safety.Marker`

Possible outcomes:

- `carrier_candidates_found`
- `no_candidate_found`
- `only_rejected_candidates_found`
- `carrier_discovery_unsupported`
- `carrier_discovery_crash_suspect`

## 4. `p2p-carrier-visibility-watch`

Purpose: observe whether candidates are visible across roles/peers.

Allowed observations:

- Read-only candidate visibility.
- Natural value change observation.
- Direction classification:
  - `local-only`
  - `host-to-client`
  - `client-to-host`
  - `client-to-client`
  - `host-only`
  - `joined-client-only`
  - `all-visible`
  - `unknown`
- Role, context, and lifecycle tags.

Forbidden:

- Synthetic payloads.
- Writes.
- RPCs.
- Mutation.
- Forcing gameplay state changes.

Expected evidence row families:

- `P2PCarrier.Visibility.Sample`
- `P2PCarrier.Lifecycle.Sample`
- `P2PCarrier.Safety.Marker`

Possible outcomes:

- `visibility_confirmed`
- `visibility_partial`
- `visibility_local_only`
- `visibility_not_observed`
- `visibility_unsupported`
- `visibility_crash_suspect`

## 5. `p2p-carrier-capacity-read`

Purpose: infer capacity and cadence from naturally observed read-only values.

Allowed observations:

- Observed value kind.
- Observed string/array/scalar length if safe.
- Natural cadence of changes.
- Maximum observed natural payload size.
- No synthetic payload.

Forbidden:

- Writing test strings.
- Increasing value size.
- Forcing updates.
- Mutation.
- RPCs.

Expected evidence row families:

- `P2PCarrier.Capacity.Observation`
- `P2PCarrier.Safety.Marker`

Possible outcomes:

- `capacity_observed`
- `capacity_too_small`
- `capacity_unknown`
- `capacity_unsupported`
- `capacity_crash_suspect`

## 6. `p2p-carrier-lifecycle-watch`

Purpose: observe candidate behavior across startup, lobby, join, travel, respawn, disconnect, and reconnect if later tested.

Allowed observations:

- Candidate presence/absence.
- Stale behavior.
- Reset behavior.
- Role changes.
- Generation/lifecycle tags.

Forbidden:

- Writes.
- RPCs.
- Forced transitions beyond normal manual play.

Expected evidence row families:

- `P2PCarrier.Lifecycle.Sample`
- `P2PCarrier.Visibility.Sample`

Possible outcomes:

- `lifecycle_stable`
- `lifecycle_resets_cleanly`
- `lifecycle_stale_risk`
- `lifecycle_unstable`
- `lifecycle_unsupported`
- `lifecycle_crash_suspect`

## 7. `p2p-carrier-rejection-classification`

Purpose: classify rejected candidates into unsafe or unusable buckets.

Rejection classes:

- `gameplay-authoritative`
- `currency/progression`
- `identity/matchmaking`
- `save-persistent`
- `health/gameplay critical`
- `equipment authority`
- `inventory authority`
- `UI/user-visible deception risk`
- `local-only`
- `unstable lifecycle`
- `requires mutating RPC`
- `unknown ownership`

Expected evidence row family:

- `P2PCarrier.Rejection`

Outcome: rejected candidates become entries or updates in [P2P Carrier Unsafe Paths](P2P_CARRIER_UNSAFE_PATHS.md). Rejection as a carrier does not invalidate safe read evidence for normal read-only planning.

## 8. `p2p-carrier-summary-import`

Purpose: future docs/import tooling consumes evidence rows and updates:

- [P2P Carrier Candidates](P2P_CARRIER_CANDIDATES.md)
- [P2P Carrier Visibility Matrix](P2P_CARRIER_VISIBILITY_MATRIX.md)
- [P2P Carrier Unsafe Paths](P2P_CARRIER_UNSAFE_PATHS.md)

This tooling is not implemented now.

Summary import rules:

- Preserve evidence honesty.
- Do not promote any write-smoke candidate automatically without human review.
- Do not modify old evidence meaning.
- Do not convert read evidence into write evidence.
- Keep unsupported and rejected outcomes visible.

## 9. `p2p-carrier-write-smoke` Boundary

`p2p-carrier-write-smoke` is not a RuntimeProbe default phase, is not implemented by this task, and is not authorized by this task.

It is future CrabSyncV2-only sandbox work and requires:

- `visibility-confirmed` or `capacity-observed` candidate.
- Candidate absent from unsafe paths.
- Explicit user approval.
- Manual disposable test environment.
- Clear/reset plan.
- Rollback/abort criteria.

Passing write-smoke only creates an experimental capability candidate. It does not create production-safe transport.

## 10. Phase Result Vocabulary

Standardized result names:

- `carrier_candidates_found`
- `no_candidate_found`
- `only_rejected_candidates_found`
- `visibility_confirmed`
- `visibility_partial`
- `visibility_local_only`
- `capacity_observed`
- `lifecycle_stable`
- `lifecycle_stale_risk`
- `carrier_discovery_unsupported`
- `carrier_discovery_crash_suspect`
- `carrier_research_failed_no_sample`

## 11. Relationship To Existing Docs

This document feeds:

- [CrabSyncV2 P2P Carrier Research Plan](CRABSYNCV2_P2P_CARRIER_RESEARCH_PLAN.md).
- [P2P Carrier Evidence Mapping](P2P_CARRIER_EVIDENCE_MAPPING.md).
- [P2P Carrier Candidates](P2P_CARRIER_CANDIDATES.md).
- [P2P Carrier Visibility Matrix](P2P_CARRIER_VISIBILITY_MATRIX.md).
- [P2P Carrier Unsafe Paths](P2P_CARRIER_UNSAFE_PATHS.md).
- [P2P Carrier Write-Smoke Plan](P2P_CARRIER_WRITE_SMOKE_PLAN.md).
- Future CrabSyncV2 readiness checklist documentation.

These contracts are prerequisites for future carrier research implementation discussions. They do not by themselves unblock CrabSyncV2 implementation.
