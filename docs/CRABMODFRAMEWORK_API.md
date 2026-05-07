# CrabModFramework API Plan

CrabModFramework is planned as a Crab Champions-specific safety layer on top of UE4SS. It does not replace UE4SS as the loader. The goal is to give mod authors a controlled API for common Crab Champions operations so they do not need to reach for raw UE4SS calls by default.

RuntimeProbe remains the read-only evidence engine. Evidence collected here proves read paths, contexts, gates, and failure modes. It does not grant permission to write, call RPCs, mutate DataAssets, traverse live inventory arrays, or call gameplay functions.

The proposed future API contract is detailed in [CrabModFramework API Contract](CRABMODFRAMEWORK_API_CONTRACT.md). Capability declarations and status resolution are detailed in [CrabModFramework Capability Model](CRABMODFRAMEWORK_CAPABILITY_MODEL.md). Mod author usage guidance is in [CrabModFramework Modding Guide](CRABMODFRAMEWORK_MODDING_GUIDE.md).

## Planned Surfaces

- `framework-skeleton`: package layout, lifecycle hooks, versioning, and shared diagnostics.
- `safe-context-api`: stable access to current runtime context, role, lifecycle, and safety gate state.
- `safe-playerstate-api`: CrabPC -> PlayerState -> CrabPS access helpers for paths proven safe by RuntimeProbe.
- `safe-dataasset-catalog-api`: read cached DataAsset catalog evidence through typed definitions.
- `safe-property-read-wrappers`: property reads with known owner/class/path, result classification, nil handling, and evidence tags.
- `safe-event-watcher-wrappers`: passive observers for game-called events and functions, without invoking those functions.
- `capability-declarations`: mod manifests declare which safe APIs and experimental capabilities they use.
- `direct-ue4ss-call-linting`: validation that flags raw UE4SS calls outside approved framework wrappers.
- `experimental-write-api`: future-only controlled edits/writes, separate from RuntimeProbe and requiring explicit safety review.

## DataAsset Direction

The first implemented RuntimeProbe catalog phase is `perk-da-catalog-read`. It reads a capped, curated list of perk DataAsset-like objects and curated fields. TastyOrange and Collector are not special-cased; they are normal catalog entries only if discovered safely.

Future API work may expose this as a read-only definition catalog first. Any edit/write surface for CrabModFramework or CrabTastyMod must be designed separately and must not be inferred from RuntimeProbe read evidence.

## Non-Goals

- No RuntimeProbe writes.
- No RuntimeProbe RPC calls.
- No HUD hook dependency.
- No live inventory array traversal.
- No InventoryInfo or Enhancements access until explicitly reviewed.
- No wiki-specific workflow; `docs/` is the source of truth.
