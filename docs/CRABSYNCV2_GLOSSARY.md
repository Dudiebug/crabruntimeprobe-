# CrabSyncV2 Glossary

`objectdump`: Static UE4SS dump data showing that symbols exist. It is not runtime safety proof.

`runtime evidence`: Imported in-game JSONL/manifest/log-derived facts from CrabRuntimeProbe sessions.

`probe result`: A row in `probe_results_<session>.jsonl` describing a probe or observe event result.

`access evidence`: A normalized row in `access_evidence_<session>.jsonl` used to build safe access docs.

`session manifest`: `session_manifest_<session>.json`, recording config, gates, build info, probe set, and tick driver.

`observe mode`: Passive context sampling mode that does not run registry probes.

`active mode`: Pacing/gated mode that runs curated probes one at a time.

`safety gate`: A config flag that must be explicitly enabled for a research category.

`lifecycle gate`: A rule that reads/applies only happen after startup, travel, respawn, join, and similar unstable windows settle.

`role gate`: A rule that behavior depends on stable role, such as solo/host/joined-client/unknown.

`PlayerState-scoped`: An access path that starts from local `CrabPC -> PlayerState -> CrabPS`.

`unscoped object lookup`: A lookup such as `FindFirstOf(CrabHC)` that is not tied to the player path and may return non-player objects.

`userdata shape`: Evidence that a value is a Lua userdata wrapper; it does not prove count, traversal, or contents.

`traversal`: Iterating through an array/container.

`element dereference`: Converting an array wrapper/element into the underlying object, such as calling a wrapper `get()`.

`InventoryInfo`: Item metadata structure expected to hold fields such as `Level`, `AccumulatedBuff`, and `Enhancements`; runtime item reads are not yet proven.

`Enhancements`: Nested item upgrade metadata needed for preserving upgrade state; not yet proven safe to read.

`DA identity`: Data asset identity, preferably full path/name when safe, used to identify equipment or items.

`stable generation`: A repeated, unchanged read generation over multiple ticks before trust/apply.

`local-only field`: Runtime-visible state that CrabSyncV2 may diagnose but must not include in shared merge/apply payloads.

`progression currency`: Currency tied to permanent or new-content unlocks rather than the current shared run.

`keys`: Local-only progression/unlock currency that must not be included in CrabSyncV2 shared state.

`relay/server`: External or host-mediated carrier/merge authority that may be needed if P2P inventory metadata is not visible.

`P2P piggyback carrier`: A hypothesized safe path for attaching additional CrabSyncV2 state to a proven player/health/resource sharing path without an external relay.

`external relay fallback`: The architecture fallback where inventory/resource metadata is exchanged through an external or host-mediated relay if no safe P2P piggyback carrier is proven.

`P2P merge`: Peer-to-peer state merge using visible PlayerState/resource evidence without a dedicated relay.

`apply`: Mutating game state to match a planned state. This is future CrabSyncV2 work, not RuntimeProbe.

`plan`: A computed set of intended changes before any apply/write.

`skip`: A deliberate no-op with a logged reason when safety, lifecycle, evidence, or merge rules are not satisfied.

`mutating RPC`: A game function call that changes authoritative/gameplay state.

`OnRep`: Unreal replication notification function, often related to replicated property UI/state refresh; must be tested before relying on it.
