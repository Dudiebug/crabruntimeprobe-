# CrabRuntimeProbe

CrabRuntimeProbe is a standalone UE4SS Lua diagnostic/research mod for Crab Champions. It is designed to discover safe runtime access patterns by correlating object-dump metadata with controlled in-game runtime probes.

## Non-goals
- Not CrabInvSync
- No inventory sync
- No gameplay state writes
- No mutating RPC calls

## Install
1. Copy `client/Mods/CrabRuntimeProbe` into your UE4SS `Mods` folder.
2. Ensure `enabled.txt` exists.
3. Configure `Scripts/config.txt`.

## Observe mode
- Set `mode = observe`
- Keep deep gates disabled (default)
- Run normal gameplay; probe framework logs low-risk facts and breadcrumbs

## Active probes
- Set `mode = active`
- Enable only one gated area at a time
- Runner executes one probe step each interval with cooldown and breadcrumbing

## Crash artifact collection
After a crash, collect:
- `UE4SS.log`
- `client/Mods/CrabRuntimeProbe/Scripts/results/*.jsonl`

## Docs generation
- `node tools/parse_objectdump.js`
- `node tools/generate_probe_candidates.js`
- `node tools/summarize_probe_results.js --results <path> --ue4ss-log <path>`
- `node tools/generate_docs.js`

## First safe run
```
mode = observe
probeSet = shallow-core
allowDeepArrayProbes = false
allowInventoryInfoProbes = false
allowHealthProbes = false
allowWriteProbes = false
allowRpcProbes = false
```

1. Launch game.
2. Sit in menu 30 seconds.
3. Enter lobby.
4. Start solo island.
5. Pick up one item if convenient.
6. Quit.
7. Collect UE4SS.log and probe JSONL.
8. Run summarizer.

## Acceptance criteria targets
- Standalone CrabRuntimeProbe mod exists.
- Observe mode without deep item reads.
- JSONL results + breadcrumbs.
- Safe defaults and curated registry.
- Object dump parser and summarizer tooling.
- SAFE_ACCESS_MATRIX generation.
- No write/RPC behavior by default.
