# CrabModFramework DataAsset Catalog

RuntimeProbe DataAsset catalog phases are read-only evidence collection. They catalog definitions so future CrabModFramework or CrabTastyMod-style mods can understand game definitions through a controlled framework.

Catalog evidence is not permission to mutate DataAssets. RuntimeProbe proves read paths only. Future write or edit APIs must be designed separately in CrabModFramework, capability-gated, and reviewed.

## Implemented Phase

`perk-da-catalog-read` discovers perk DataAsset-like objects through curated class/name patterns and capped `FindAllOf` usage. It reads only curated fields, class/name identity, validity, and object reference summaries without recursion.

TastyOrange is not special-cased by RuntimeProbe. It appears only as a normal perk catalog entry if safely found.

Collector is not special-cased by RuntimeProbe. It appears only as a normal perk catalog entry if safely found.

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

## Safety Contract

Required markers are `noWrites`, `noRpcs`, `noHud`, `noDeepArrays`, `noInventoryArrays`, `noArrayCount`, `noArrayTraversal`, `noElementDereference`, `noInventoryInfo`, `noEnhancements`, `noDataAssetMutation`, and `noFunctionCalls`.

The narrow gate is `allowPerkDataAssetCatalogProbes`. The phase must keep unrelated gates disabled, including safe scalar watch, slots, crystals, health, identity, raw identity, inventory array, InventoryInfo, deep array, write, RPC, HUD, and unknown-role gates.

## Future Catalog Phases

- `weaponmod-da-catalog-read`.
- `abilitymod-da-catalog-read`.
- `meleemod-da-catalog-read`.
- `weapon-da-catalog-read`.
- `ability-da-catalog-read`.
- `melee-da-catalog-read`.

These remain placeholders until implemented and reviewed separately.
