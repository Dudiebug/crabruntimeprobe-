# CrabRuntimeProbe

CrabRuntimeProbe is a standalone UE4SS Lua diagnostic/research mod for Crab Champions. It is built to safely discover runtime read-access behavior and crash boundaries from real sessions.

## Non-goals
- Not CrabInvSync.
- No gameplay sync.
- No gameplay writes.
- No mutating RPC calls.

## Install
1. Copy `client/Mods/CrabRuntimeProbe` into your UE4SS `Mods` folder.
2. Ensure `enabled.txt` exists.
3. Keep default `Scripts/config.txt` for first run.

## First safe run
Use:
- `mode = observe`
- `probeSet = shallow-core`
- `allowDeepArrayProbes = false`
- `allowInventoryInfoProbes = false`
- `allowHealthProbes = false`
- `allowWriteProbes = false`
- `allowRpcProbes = false`

Then:
1. Launch game.
2. Sit in menu 30 seconds.
3. Enter lobby.
4. Start solo island.
5. Pick up one item if convenient.
6. Quit.
7. Collect UE4SS.log and probe JSONL.
8. Run summarizer.

## Observe mode
Passive low-risk collection only. No deep item array reads, no `elem:get()` on inventory arrays, no InventoryInfo reads.

## Active probes
One probe step every interval with breadcrumbs before/after each risky operation.

## Crash collection
Collect:
- `UE4SS.log`
- `Mods/CrabRuntimeProbe/Scripts/results/*.jsonl`
- `Mods/CrabRuntimeProbe/Scripts/results/*.log`

## Docs generation
- `node tools/parse_objectdump.js`
- `node tools/generate_probe_candidates.js`
- `node tools/summarize_probe_results.js --results <jsonl> --ue4ss-log <UE4SS.log>`
- `node tools/generate_docs.js`
