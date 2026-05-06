# Write Path Observed Natural Calls

This is a future status document for passive observation of natural game calls, events, and property changes. RuntimeProbe must not make calls, force RPCs, write properties, or synthesize values. Observation is evidence input, not write approval.

## 1. Purpose

The purpose of this document is to record how Crab Champions naturally mutates state so future CrabSyncV2 planning can prefer official game paths over raw writes.

No natural-call evidence rows exist in this template today.

## 2. Natural Observation Row Schema

| Observation ID | Session ID | Timestamp | Phase ID | Category | Function/Event/Property | Object/Class | Caller/owner/source | Local role | Remote role | Context | Lifecycle state | Arguments observed? | Arguments redacted? | Pre-state summary | Post-state summary | OnRep/UI follow-up | Persistence observed? | Crash suspicion | Dirty evidence? | Result | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| none | none | none | none | none | none | none | none | unknown | unknown | unknown | unknown | no | yes | none | none | none | unknown | no | no | no current observations | Future passive observations belong here. |

## 3. Candidate Families To Observe Naturally

### Equipment Equip/Set Flows

Observe equipment changes caused by normal gameplay, not synthetic calls.

### Slot Increment Flows

Observe natural slot changes and UI updates, not manual slot mutation.

### Pickup/Inventory Acquisition Flows

Observe pickup and inventory acquisition flows during normal play.

### Inventory Removal/Equip Flows

Observe inventory removal/equip behavior during normal play.

### Crystal Change Flows

Observe natural crystal changes. Do not use crystals as a custom carrier.

### Health Change/Death/Respawn Flows

Observe PlayerState-scoped health behavior and lifecycle windows. Do not use unscoped `FindFirstOf(CrabHC)`.

### Armor Plate Flows

Observe armor behavior only if read-safe surfaces are established.

### UI Refresh Flows

Observe UI refresh behavior passively. HUD/UI observation remains read-only unless separately approved.

### P2P Carrier Natural Value Changes

Observe natural carrier-candidate value changes read-only. Carrier write-smoke remains governed by carrier readiness and sandbox rules.

## 4. Observation Rules

- Do not synthesize values.
- Do not call functions.
- Do not force RPCs.
- Do not write properties.
- Manual gameplay can naturally trigger observed flows.
- Mark evidence dirty or crash-suspect when appropriate.
- Raw/private identity redaction remains default.

## 5. Promotion Rules

- Natural call observed -> may update [Write Path Ledger](WRITE_PATH_LEDGER.md).
- Natural before/after observed -> may improve confidence.
- Authority/lifecycle observed -> may refine status.
- Conflicting or dirty evidence keeps path unresolved.
- No automatic promotion to sandbox write-smoke.
