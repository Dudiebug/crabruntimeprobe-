# CrabModFramework DataAsset Catalog

RuntimeProbe DataAsset catalog phases are read-only evidence collection. They catalog definitions so future CrabModFramework or CrabTastyMod-style mods can understand game definitions through a controlled framework.

Catalog evidence is not permission to mutate DataAssets. RuntimeProbe proves read paths only. Future write or edit APIs must be designed separately in CrabModFramework, capability-gated, and reviewed.

## Current Exported Evidence

The current canonical perk catalog export comes from imported max-safe-play session `20260506T032658Z` at source commit `2681213933be20a2e95d432bbd3531ef045077d4`.

- Evidence doc: [`docs/PERK_DATAASSET_CATALOG.md`](PERK_DATAASSET_CATALOG.md)
- Machine-readable JSON: [`docs/data/perk_dataasset_catalog.latest.json`](data/perk_dataasset_catalog.latest.json)
- Machine-readable CSV: [`docs/data/perk_dataasset_catalog.latest.csv`](data/perk_dataasset_catalog.latest.csv)

That selected snapshot contains:

- `candidateCount = 64`
- `entryCount = 64`
- `rejectedCount = 0`
- `knownEntryCount = 64`
- `tastyOrangeFound = true`
- `collectorFound = false`

TastyOrange is present as an ordinary catalog row. RuntimeProbe does not special-case it, and CrabModFramework should not special-case it when ingesting catalog evidence.

## Implemented Phase

`perk-da-catalog-read` discovers perk DataAsset-like objects through curated class/name patterns and capped `FindAllOf` usage. It reads only curated fields, class/name identity, validity, and object reference summaries without recursion. Candidate count is not the same thing as accepted catalog entries: every candidate must pass capped class/name/identity checks before it becomes a catalog entry.

Rejected candidates are summarized with capped diagnostics: candidate index, safe short/full name summaries when available, safe class summary when available, and rejection reason. Reasons include class/name filter mismatch, invalid UObject, missing objectdump-derived DataAsset reference, field read errors, unsupported value types, and duplicate catalog entries.

A safely identified perk-like DataAsset may emit a minimal identity entry even when no allowlisted tuning fields are readable. Those entries are still useful evidence because they prove safe identity/path/class visibility; their `readStatus` and `fieldResults` explain that tuning fields were nil, errored, or unsupported.

`max-safe-play-recorder` reuses this capped perk catalog logic during long normal play sessions. It records the first full snapshot, newly discovered perk DataAssets, changed readable fields, candidate/rejection counts, top rejection reasons, and compact heartbeat summaries. It does not special-case TastyOrange or Collector; either may appear only as a normal catalog entry if safely found.

TastyOrange is not special-cased by RuntimeProbe. It appears only as a normal perk catalog entry if safely found.

Collector is not special-cased by RuntimeProbe. It appears only as a normal perk catalog entry if safely found.

## What CrabModFramework Can Use Now

The exported JSON/CSV are useful as a read model for future CrabModFramework work:

- Stable catalog index, short name, full name, and source class for each discovered perk DataAsset.
- Per-field read status, value kind, and value summary for each captured field.
- A clean distinction between decoded scalar/enum values and unresolved object-reference summaries.
- A field coverage matrix that shows which fields are readable today and which still need decoder work.

This is enough to design a safe read-only `safe-dataasset-catalog-api` that exposes catalog evidence as typed definitions plus unresolved-field metadata.

## Decoder Boundary

The current exported evidence shows three broad categories:

- Already useful scalar/enum values: `Rarity`, `PerkType`, and `Cooldown`.
- Enum-shaped fields that still need decoding: `PerkRarity`, `Tier`, `PerkTier`, `Type`, and `Category`.
- Object-reference summaries that still need decoding: `DisplayName`, `Description*`, `Icon`, `Tags`, `GameplayTag`, `BaseValue`, `Value`, `Multiplier`, stack fields, weight/duration fields, and the current `b*` flags.

`Icon` is helpful because the object reference summary already exposes texture asset full names, but it is still not a decoded scalar/enum value. The same conservative rule applies to every `object_ref` field in the current export.

## Catalog Row Shape

Each discovered entry should record:

- Short name.
- Full name or path.
- Class name.
- `IsValid` result.
- Stable catalog index.
- Curated field read records.
- Enum, scalar, bool, string/text/name field summaries.
- Object reference summaries only: exists, valid, class/full name if safe.

Each field read records the field name, read status, value kind, and value summary. Object references are summarized only; nested fields are not walked.

The current exported JSON keeps this shape and also splits fields into:

- `scalarFields`
- `enumFields`
- `objectRefFields`
- `unresolvedFields`
- `decodeNeededFields`

## Safety Contract

Required markers are `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noInventoryArrays`, `noArrayCount`, `noArrayTraversal`, `noElementDereference`, `noInventoryInfo`, `noEnhancements`, `noDataAssetMutation`, `noFunctionCalls`, and `passiveOnly`.

The narrow gate is `allowPerkDataAssetCatalogProbes`. The phase must keep unrelated gates disabled, including safe scalar watch, slots, crystals, health, identity, raw identity, inventory array, InventoryInfo, deep array, write, RPC, HUD, and unknown-role gates.

The direct max-safe recorder uses `allowMaxSafePlayRecorderProbes` instead of requiring users to enable `allowPerkDataAssetCatalogProbes` separately. It must still keep the perk catalog capped, read-only, non-mutating, and free of DataAsset function calls.

RuntimeProbe catalog evidence is not permission to mutate DataAssets.

CrabModFramework write/edit APIs remain future work. Any eventual DataAsset editing must be explicit framework functionality with its own capability declarations, safety review, and non-RuntimeProbe validation path.

## Future Catalog Phases

- `weaponmod-da-catalog-read`.
- `abilitymod-da-catalog-read`.
- `meleemod-da-catalog-read`.
- `weapon-da-catalog-read`.
- `ability-da-catalog-read`.
- `melee-da-catalog-read`.

These remain placeholders until implemented and reviewed separately.
