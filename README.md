# CrabRuntimeProbe

CrabRuntimeProbe is a standalone UE4SS Lua diagnostic/research mod for Crab Champions.

It is designed to help reverse engineer **safe runtime access rules** by combining:
- object dump evidence (what fields/functions exist), and
- runtime probe evidence (what is actually safe to read in live sessions).

## Non-goals

This is **not** CrabInvSync.

This project does **not**:
- implement inventory sync,
- implement shared inventory,
- write gameplay state,
- call mutating RPCs by default.

## Repo layout

- `client/Mods/CrabRuntimeProbe/Scripts/`: UE4SS Lua runtime and probe framework.
- `client/Mods/CrabRuntimeProbe/Scripts/results/`: preferred runtime result output path.
- `objectdump/`: raw dump inputs and indexed metadata.
- `tools/`: Node.js parsing/summarization/doc generation tools.
- `docs/`: generated and curated research docs.

## Install

1. Copy `client/Mods/CrabRuntimeProbe/` into your Crab Champions UE4SS `Mods/` folder.
2. Ensure `enabled.txt` exists in that mod directory.
3. Confirm `Scripts/config.txt` uses safe defaults (provided below).

## Safe defaults (`config.txt`)

```ini
enabled = true
mode = observe

debugBreadcrumbs = true
writeJsonlResults = true
writeMarkdownSnapshots = false

probeIntervalTicks = 10
startupWarmupTicks = 60
contextStableTicksRequired = 10
maxProbesPerSession = 100

allowUnknownRoleProbes = false
allowJoinedClientDeepProbes = false
allowDeepArrayProbes = false
allowInventoryInfoProbes = false
allowHealthProbes = false
allowWriteProbes = false
allowRpcProbes = false

probeSet = shallow-core
```

## Observe mode

`mode = observe` is passive low-risk collection while playing.

It records facts such as:
- session/tick/context/role guesses,
- lifecycle transitions,
- PC/PS existence & validity checks,
- safe shallow probe results,
- breadcrumbs around operations.

It avoids deep inventory reads and risky health/inventory info operations unless explicitly enabled.

## Active mode

`mode = active` runs controlled probes one at a time.

Safety behavior:
- startup warmup,
- context stabilization gate,
- one probe step per interval,
- breadcrumb before/after risky operations,
- config/context-based skip outcomes,
- hard cap via `maxProbesPerSession`.

## Crash data collection

After a crash, collect:
- `UE4SS.log`,
- JSONL results from `Scripts/results/` (or `Scripts/` fallback).

`tools/summarize_probe_results.js` can infer `CRASH_SUSPECT` from the last unmatched breadcrumb.

## Object dump & docs tooling

- `node tools/parse_objectdump.js`
- `node tools/generate_probe_candidates.js`
- `node tools/summarize_probe_results.js --results <probe_results.jsonl> --ue4ss-log <UE4SS.log>`
- `node tools/generate_docs.js`

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

## Warnings

Write/RPC probes are intentionally disabled by default. Do not enable mutating behavior until read-only runtime safety is established.
