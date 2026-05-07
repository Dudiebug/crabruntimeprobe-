# CrabModFramework Capability Model

This is future architecture documentation. It does not implement CrabModFramework, authorize RuntimeProbe writes, expose runtime capabilities today, or permit mutating RPCs.

## 1. Purpose

Define capability declarations and statuses for future CrabModFramework wrappers.

Capabilities control which wrappers a mod may use. Capabilities are evidence-backed and must be checked against role, lifecycle, crash-suspect state, unsafe paths, and experimental approval.

Unsupported or unavailable capabilities must not be used.

## 2. Capability Status Values

| Status | Meaning |
|---|---|
| `unavailable` | No framework capability exists today. |
| `objectdump-only` | Static symbol exists, but runtime safety is unproven. |
| `runtime-confirmed-local` | Local read path is confirmed under scoped RuntimeProbe evidence. |
| `runtime-confirmed-remote` | Remote/visible read path is confirmed under scoped evidence. |
| `runtime-confirmed-host` | Host-context behavior is confirmed under scoped evidence. |
| `runtime-confirmed-joined-client` | Joined-client behavior is confirmed under scoped evidence. |
| `unsupported` | Evidence shows the path is unavailable or not safely usable. |
| `unsafe` | Path is forbidden or too risky. |
| `crash-suspect` | Evidence or runtime state suggests instability. |
| `diagnostic-only` | Useful for logs/observation, not readiness promotion. |
| `experimental` | Future manually approved capability with narrow gates. |
| `production-gated` | Future only; requires repeated clean evidence, review, and capability gates. |

## 3. Capability Declaration Model

A future mod declares:

- Capability name.
- Required status.
- Allowed roles.
- Allowed lifecycle states.
- Fallback behavior.
- Diagnostics category.
- Whether experimental writes are requested.
- Whether raw identity evidence is requested.

Raw identity requests should default to denied unless a future explicit policy and evidence path allow them.

## 4. Read Capabilities

| Capability | Current Planning Status |
|---|---|
| `read.context` | Future framework wrapper; evidence-backed by context docs. |
| `read.identity.redacted` | Runtime-confirmed redacted/fingerprinted planning target. |
| `read.equipment.local` | Runtime-confirmed local read planning target. |
| `read.equipment.remote` | Runtime-confirmed/partial remote planning target. |
| `read.resources.local` | Runtime-confirmed local scalar planning target. |
| `read.resources.remote` | Runtime-confirmed/partial remote scalar planning target. |
| `read.health.local` | Runtime-confirmed PlayerState-scoped planning target. |
| `read.health.remote` | Runtime-confirmed/partial remote planning target. |
| `read.inventory.shape.local` | Runtime-confirmed local shape planning target. |
| `read.inventory.count.local` | Runtime-confirmed local count-metadata planning target. |
| `read.inventory.item_identity.local` | Future gated by `inventory-element-da-read`. |
| `read.inventory.inventoryinfo.local` | Unavailable until `inventoryinfo-scalar-read`. |
| `read.inventory.enhancements.local` | Unavailable until `enhancements-read`. |
| `read.inventory.item_identity.remote` | Unavailable until remote inventory proof. |
| `read.inventory.inventoryinfo.remote` | Unavailable until remote metadata proof. |
| `read.dataassets.perk_catalog` | Runtime-confirmed read-only catalog planning target. |
| `read.dataassets.weaponmod_catalog` | Future/unavailable. |
| `read.dataassets.abilitymod_catalog` | Future/unavailable. |
| `read.dataassets.meleemod_catalog` | Future/unavailable. |
| `read.dataassets.relic_catalog` | Future/unavailable. |

## 5. P2P Capabilities

| Capability | Current Planning Status |
|---|---|
| `p2p.visible_state.derive` | Future helper for evidence-backed visible state only. |
| `p2p.health.convergence` | Future read-only convergence, gated by health model evidence. |
| `p2p.resources.convergence` | Future read-only convergence, gated by resource model evidence. |
| `p2p.carrier.discovery.read` | Future read-only carrier discovery. |
| `p2p.carrier.visibility.read` | Future read-only carrier visibility watch. |
| `p2p.carrier.capacity.read` | Future read-only capacity/cadence observation. |
| `p2p.carrier.read` | Future only after carrier readiness. |
| `p2p.carrier.write.experimental` | Future only; unavailable today and requires approval plus write-smoke evidence. |

## 6. Write Capabilities

All write capabilities are unavailable today, future/experimental only, not RuntimeProbe, and require safe write-path discovery, sandbox smoke evidence, and explicit user approval.

| Capability | Status |
|---|---|
| `write.equipment.experimental` | Unavailable today. |
| `write.slots.experimental` | Unavailable today. |
| `write.crystals.experimental` | Unavailable today. |
| `write.health.experimental` | Unavailable today. |
| `write.inventory.experimental` | Unavailable today. |
| `write.inventory.metadata.experimental` | Unavailable today. |
| `write.inventory.enhancements.experimental` | Unavailable today. |
| `write.ui_refresh.experimental` | Unavailable today. |
| `write.p2p_carrier.experimental` | Unavailable today. |

No write capability may be promoted from objectdump-only, function-presence-only, read visibility, or carrier readiness alone.

## 7. Forbidden Capabilities

These capabilities are forbidden unless future explicit re-approval and evidence reclassify them. Reclassification is not expected or assumed.

- `write.keys`.
- `write.unlocks`.
- `write.progression`.
- `write.identity`.
- `write.autosave.raw`.
- `carrier.crystals`.
- `carrier.healthinfo`.
- `carrier.equipment_da`.
- `carrier.num_slots`.
- `carrier.inventory_arrays`.
- `carrier.inventoryinfo`.
- `carrier.playername`.
- `carrier.uniqueid`.

## 8. Capability Resolution Algorithm

Future capability resolution should follow this order:

1. Receive requested capability.
2. Check evidence status.
3. Check role.
4. Check lifecycle.
5. Check crash-suspect state.
6. Check unsafe paths.
7. Check experimental approval if requested.
8. Return `allowed`, `denied`, `unsupported`, `unsafe`, or `stale`.

Denied or unsupported capabilities must produce a skip reason and must not fall back to raw UE4SS access.

## 9. Capability Examples

These are fictional non-implementation examples:

- CrabSyncV2 requests `read.health.remote` and receives `runtime-confirmed-remote` for read-only convergence.
- CrabSyncV2 requests `read.inventory.inventoryinfo.local` and receives `unavailable` until `inventoryinfo-scalar-read`.
- CrabSyncV2 requests `p2p.carrier.write.experimental` and receives `denied` until carrier readiness, explicit approval, and write-smoke evidence exist.
- CrabTastyMod requests `read.dataassets.perk_catalog` and receives a read-only catalog capability.
- Any mod requests `write.keys` and receives forbidden/unsafe.

## 10. Future Linting

Future linting should flag:

- Direct raw UE4SS calls outside wrappers.
- Mutating calls outside `ExperimentalWrite`.
- Broad object crawling.
- Identity or raw private values.
- `InventoryInfo` or `Enhancements` access unless the capability exists.
