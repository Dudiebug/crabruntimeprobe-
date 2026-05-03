# CrabRuntimeProbe

CrabRuntimeProbe is a standalone UE4SS Lua diagnostic/research mod for Crab Champions.
It helps reverse engineer **safe runtime access rules** by combining object dump presence with in-session probe observations.

## Why this exists

UE4SS object dumps show what symbols exist, but not when/where access is safe. This project captures runtime facts with paced, breadcrumbed probing.

## Safety and non-goals

- NOT CrabInvSync.
- No inventory sync/shared inventory.
- No gameplay state writes by default.
- No mutating RPC calls by default.
- No packaged UE4SS or game binaries.

## Install

1. Copy `client/Mods/CrabRuntimeProbe` into your UE4SS mods directory.
2. Ensure `enabled.txt` contains `1`.
3. Edit `Scripts/config.txt` as needed.

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

## Modes

- `observe`: passive low-risk collection while playing.
- `active`: controlled one-probe-at-a-time execution with pacing and gates.

## Result files

- Primary: `client/Mods/CrabRuntimeProbe/Scripts/results/*.jsonl`
- Fallback: `client/Mods/CrabRuntimeProbe/Scripts/*.jsonl`

## Docs generation

- `node tools/parse_objectdump.js`
- `node tools/generate_probe_candidates.js`
- `node tools/summarize_probe_results.js --results <path> [--ue4ss-log <path>]`
- `node tools/generate_docs.js`

## Crash collection

After a crash collect:

- `UE4SS.log`
- latest probe `.jsonl`
- active `config.txt`

`tools/summarize_probe_results.js` infers `CRASH_SUSPECT` from final unmatched breadcrumb.
