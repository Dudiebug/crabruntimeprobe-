# CrabSyncV2 Design Rules

These are future CrabSyncV2 constraints. They do not authorize RuntimeProbe writes.

## Runtime/Lifecycle

- No apply/write during unknown role, startup, loading, travel, respawn, join, disconnect, or unstable local player state.
- Require stable PlayerState and stable generation for multiple ticks before trusting reads.
- Joined clients default to read-only/no-apply until specific joined-client evidence proves safety.
- Reset stale push/recv/apply state on role/lifecycle transitions.

## Health

- Player health source must start with `CrabPC -> PlayerState -> CrabPS -> HealthInfo`.
- Do not use unscoped `FindFirstOf(CrabHC)` for player health.
- Pooled/shared health is a CrabSyncV2 design concept, not a vanilla RuntimeProbe fact.
- Multiplayer max-health math remains evidence-gated.
- Armor policy remains unresolved until documented evidence exists.

## Inventory

- Do not compare inventory arrays by DA name only.
- Do not rebuild item arrays unless full `InventoryInfo` can be preserved.
- Item identity must eventually include DA short name, preferably full DA identity/path if safe, `Level`, `AccumulatedBuff`, and `Enhancements`.
- `InventoryInfo.Level` is byte-like and must be clamped safely.
- `Enhancements` are required for Anvil upgrade preservation.
- `AccumulatedBuff` must be finite and should not be assumed non-negative unless evidence proves it.
- Duplicate same-name items must not be collapsed unless the game representation proves same-DA entries are stack-only.
- Reordering alone should not trigger destructive apply.

## Resources

- Slot fields are byte range and must clamp to `0..255`.
- Crystals are UInt32 range and must clamp to `0..4294967295`.
- DO NOT SYNC KEYS. this is because keys are the currency used by the player to unlock new content.

## Networking/Merge

- Server/relay merge must preserve metadata.
- Do not emit values outside objectdump-backed property ranges.
- Do not let one stale client overwrite safer local runtime state.
- Prefer generation/timestamp/role-aware merge policy over blind last-write-wins.
- It may be possible to do P2P Syncing by piggybacking off of health data share and adding info ontop of that, sharing inventory and other info between players instead of doing it through a external relay.

## RPCs/Writes

- RuntimeProbe must not call mutating RPCs.
- CrabSyncV2 may test official RPCs separately only behind explicit safety gates and with manual test phases.
- Raw writes should be fallback only after official paths are proven unusable.
- OnRep/UI refresh behavior must be tested before relying on it.
