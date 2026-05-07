# Write Path Ledger

This is a future status ledger for CrabSyncV2 write/apply candidate paths. No path is approved today unless future evidence explicitly proves it. This ledger is a planning/status artifact, not permission to write, call RPCs, mutate fields, or implement CrabSyncV2.

RuntimeProbe remains read-only.

[Write Path Evidence Mapping](WRITE_PATH_EVIDENCE_MAPPING.md) defines how future passive evidence rows may create or update ledger rows. Mapping evidence into this ledger does not approve a write.

## 1. Purpose

The ledger records candidate write/apply paths after passive observation and later CrabSyncV2-only sandbox evidence. It separates static symbol presence, passive natural observation, sandbox smoke, and production readiness.

## 2. Write Path Status Values

| Status | Meaning | What it permits | What it does not permit | Next evidence needed |
|---|---|---|---|---|
| `objectdump-only` | Static symbol exists or appears in candidate docs. | Planning inventory only. | Calling, writing, or assuming safety. | Runtime-safe passive observation plan. |
| `function-presence-confirmed` | Runtime can identify the function/event/property without calling it. | Candidate tracking. | Calling, argument replay, or mutation. | Passive natural-call observation. |
| `naturally-observed-call` | Vanilla game appears to invoke or trigger the path naturally. | Call-flow documentation. | Mimicry or sandbox smoke. | Before/after state capture. |
| `naturally-observed-before-after` | Natural pre/post state is documented. | Candidate discussion. | Write-smoke or production use. | Authority, lifecycle, persistence, UI/OnRep evidence. |
| `naturally-observed-authority` | Owner/authority role is understood from passive observation. | Role-aware planning. | Calls from unobserved roles. | Lifecycle window evidence. |
| `naturally-observed-lifecycle-window` | Natural safe-looking timing windows are documented. | Sandbox proposal preparation. | Automatic sandbox execution. | Human review and rollback/abort plan. |
| `candidate-write-path` | Evidence suggests future sandbox review may be possible. | Human review discussion. | Write-smoke without approval. | Explicit sandbox proposal. |
| `sandbox-write-smoke-proposed` | Future manual CrabSyncV2-only smoke plan exists. | Approval discussion. | Running the test without approval. | Explicit user approval. |
| `sandbox-write-smoke-passed` | Future approved smoke passed once. | Experimental capability discussion. | Production safety claim. | Repeated clean evidence. |
| `limited-write-capability` | Future limited capability has strict evidence and gates. | Narrow experimental gated use planning. | Broad sync or defaults. | Full readiness review. |
| `production-safe-gated` | Future production threshold after repeated clean evidence and review. | Production consideration only. | Skipping capability gates. | Ongoing regression and safety policy. |
| `unsafe` | Known unsafe or too risky. | Rejection documentation. | Use as write/apply path. | Different path or explicit re-review. |
| `unsupported` | Evidence cannot support the path. | Blocked status. | Apply behavior. | Alternative research. |
| `crash-suspect` | Crash or native instability may be associated. | Stop and review. | Promotion or testing. | Crash/safety analysis. |
| `diagnostic-only` | Useful only as diagnostic context. | Notes and warnings. | Readiness promotion. | Clean evidence run. |

## 3. Ledger Table Schema

| Path ID | Category | Object/Class | Function/Property/Event | Path type | Observed naturally? | Args understood? | Authority | Direction | Local role | Remote role | Lifecycle window | Pre-state captured? | Post-state captured? | UI/OnRep observed? | Persistence behavior | Side effects | Current status | Risk level | Evidence session | Next evidence needed | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| placeholder-none | none | none | none | none | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | unsupported | unknown | none | Passive observation evidence. | No write path is safe today. |

## 4. Category Sections

### Equipment

Future equipment write/apply candidate rows belong here.

### Slots

Future slot write/apply candidate rows belong here.

### Inventory Items

Future inventory item write/apply candidate rows belong here.

### Inventory Metadata

Future `InventoryInfo`, level, buff, and related metadata candidate rows belong here.

### Enhancements

Future nested enhancement candidate rows belong here.

### Crystals

Future crystal change observations belong here. `Crystals` must not be used as a custom payload carrier.

Read/convergence planning for crystals and slots is documented in [CrabSyncV2 Resource P2P Model](CRABSYNCV2_RESOURCE_P2P_MODEL.md). That model is separate from this write-path ledger and does not approve writes.

### Health

Future health write/apply candidate rows belong here. Health visibility does not authorize mutation.

Read/convergence planning for health is documented in [CrabSyncV2 Health P2P Model](CRABSYNCV2_HEALTH_P2P_MODEL.md). That model is separate from this write-path ledger and does not approve health apply.

### Armor

Future armor plate candidate rows belong here.

### UI Refresh

Future UI/OnRep refresh observations belong here. UI observation remains read-only unless separately approved.

### P2P Carrier Write-Smoke

Future carrier write-smoke rows belong here only after carrier readiness and write-smoke prerequisites are satisfied.

### Save/Persistence

Future save/persistence side-effect rows belong here.

### Identity/Session

Identity writes are forbidden unless future explicit review reclassifies a path. Raw identity and matchmaking mutation remain blocked by default.

## 5. Initial Placeholder Rows

These rows are not approvals. They record known names as unproven planning candidates or blocked raw-write families.

| Path ID | Category | Object/Class | Function/Property/Event | Path type | Observed naturally? | Args understood? | Authority | Direction | Local role | Remote role | Lifecycle window | Pre-state captured? | Post-state captured? | UI/OnRep observed? | Persistence behavior | Side effects | Current status | Risk level | Evidence session | Next evidence needed | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| equipment-server-equip-inventory | Equipment | unknown | `ServerEquipInventory` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Function presence is not call safety. |
| equipment-server-set-weapon-da | Equipment | unknown | `ServerSetWeaponDA` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| equipment-server-set-ability-da | Equipment | unknown | `ServerSetAbilityDA` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| equipment-server-set-melee-da | Equipment | unknown | `ServerSetMeleeDA` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| slots-server-increment-inventory-slots | Slots | unknown | `ServerIncrementNumInventorySlots` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| inventory-remove-weapon-mod | Inventory items | unknown | `ServerRemoveWeaponMod` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| inventory-remove-ability-mod | Inventory items | unknown | `ServerRemoveAbilityMod` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| inventory-remove-melee-mod | Inventory items | unknown | `ServerRemoveMeleeMod` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| inventory-remove-perk | Inventory items | unknown | `ServerRemovePerk` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| inventory-remove-relic | Inventory items | unknown | `ServerRemoveRelic` | RPC/function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive natural observation. | Not approved. |
| inventory-onrep-inventory | Inventory items | unknown | `OnRep_Inventory` | OnRep/event | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | high | none | Passive observation. | OnRep presence is not refresh safety. |
| crystals-onrep-crystals | Crystals | unknown | `OnRep_Crystals` | OnRep/event | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | high | none | Passive observation. | Do not use crystals as carrier. |
| equipment-onrep-weapon-da | Equipment | unknown | `OnRep_WeaponDA` | OnRep/event | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | high | none | Passive observation. | Not approved. |
| equipment-onrep-ability-da | Equipment | unknown | `OnRep_AbilityDA` | OnRep/event | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | high | none | Passive observation. | Not approved. |
| equipment-onrep-melee-da | Equipment | unknown | `OnRep_MeleeDA` | OnRep/event | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | high | none | Passive observation. | Not approved. |
| ui-client-refresh-ps-ui | UI refresh | unknown | `ClientRefreshPSUI` | client function | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | high | none | Passive observation. | UI behavior unproven. |
| inventory-client-picked-up-pickup | Inventory items | unknown | `ClientOnPickedUpPickup` | client function/event | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | unknown | objectdump-only | critical | none | Passive observation. | Pickup flow unproven. |
| raw-set-num-slots | Slots | unknown | raw `SetPropertyValue` for `Num*Slots` | raw write | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | likely gameplay | unsafe | critical | none | Official path proof first. | Raw slot writes blocked. |
| raw-set-crystals | Crystals | unknown | raw `SetPropertyValue` for `Crystals` | raw write | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | currency/progression | unsafe | critical | none | Official path proof first. | Raw crystal writes blocked. |
| raw-inventory-array-rebuild | Inventory items | unknown | raw inventory array rebuild | raw write | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | save-sensitive | destructive metadata risk | unsafe | critical | none | Full metadata preservation proof. | Destructive rebuild blocked. |
| raw-inventoryinfo-metadata | Inventory metadata | unknown | raw `InventoryInfo` metadata writes | raw write | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | save-sensitive | metadata corruption risk | unsafe | critical | none | Metadata proof and official path proof. | Blocked. |
| raw-enhancements | Enhancements | unknown | raw `Enhancements` writes | raw write | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | save-sensitive | metadata corruption risk | unsafe | critical | none | Enhancement proof and official path proof. | Blocked. |
| healthinfo-writes | Health | unknown | `HealthInfo` writes | raw/function write | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | gameplay-critical | health corruption risk | unsafe | critical | none | Passive health behavior evidence. | Health apply unproven. |
| carrier-crabsyncblock-smoke | P2P carrier write-smoke | unknown | `CrabSyncBlock` carrier write-smoke | sandbox only | no | no | unknown | unknown | unknown | unknown | unknown | no | no | no | unknown | transport risk | unsupported | critical | none | Carrier readiness and explicit approval. | Not RuntimeProbe. |

## 6. Interpretation Rules

- `objectdump-only` does not authorize a call.
- `function-presence-confirmed` does not authorize a call.
- `naturally-observed-call` does not authorize mimicry.
- Before/after observation is required before `candidate-write-path`.
- Sandbox smoke cannot be proposed automatically.
- `production-safe-gated` requires repeated clean evidence, lifecycle coverage, and explicit user approval.
