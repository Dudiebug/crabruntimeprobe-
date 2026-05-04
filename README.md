# CrabRuntimeProbe

CrabRuntimeProbe is a standalone UE4SS Lua diagnostic/research mod for Crab Champions.
It helps reverse engineer **safe runtime access rules** by combining object dump presence with in-session probe observations.

## Why this exists

UE4SS object dumps show what symbols exist, but not when/where access is safe. This project captures runtime facts with paced, breadcrumbed probing.

## Safety and non-goals

- NOT CrabInvSync.
- No inventory sync/shared inventory.
- No gameplay state writes.
- No mutating RPC calls.
- No deep inventory probes in the default foundation.
- No packaged UE4SS or game binaries.

## Install

1. Copy `client/Mods/CrabRuntimeProbe` into your UE4SS mods directory.
2. Ensure `enabled.txt` contains `1`.
3. Edit `Scripts/config.txt` as needed.

## First safe run

Use:

- `mode = observe`
- `observeIntervalTicks = 10`
- `probeSet = shallow-core`
- `allowDeepArrayProbes = false`
- `allowInventoryInfoProbes = false`
- `allowHealthProbes = false`
- `allowWriteProbes = false`
- `allowRpcProbes = false`

Then:

1. Launch game.
2. Sit in menu long enough to clear `startupWarmupTicks`.
3. Enter lobby.
4. Start solo island.
5. Do not enable active mode for the first in-game test.
6. Quit.
7. Collect UE4SS.log and probe JSONL.
8. Run summarizer.

## Modes

- `observe`: passive low-risk context sampling while playing.
- `active`: controlled one-probe-at-a-time execution with pacing and gates.

Observe mode does not run the curated probe registry. It writes `Observe.Context`
rows only, containing timestamp/session/tick/mode, context and role guesses,
lifecycle state, and safe `CrabPC`/`PlayerState` existence and validity checks.
It waits for `startupWarmupTicks`, then writes only every
`observeIntervalTicks`.

Active mode waits for startup warmup and context stability, runs at most one
registry probe per interval, emits before/after breadcrumbs, respects safety
gates, and writes JSONL results.

## Result files

- Primary: `client/Mods/CrabRuntimeProbe/Scripts/results/*.jsonl`
- Fallback: `client/Mods/CrabRuntimeProbe/Scripts/*.jsonl`

## Release packaging

CrabRuntimeProbe can build a UE4SS-bundled release ZIP from a local
CrabInvSync checkout or ZIP used only as a template for UE4SS runtime files,
UE4SS settings, support mods, and UE4SS license handling.

The packager does not copy CrabInvSync gameplay code, server files, objectdump
files, runtime logs/output, `.git`, or `node_modules`. It creates a ZIP meant to
be extracted into:

```text
Crab Champions\CrabChampions\Binaries\Win64\
```

Build from the provided local ZIP:

```powershell
node tools/package_release.js --template C:\Users\dudie\Downloads\CrabInvSync-master.zip
```

The packager uses the local `tar` command to extract and create ZIP files, so
`tar` must be available on PATH.

Optional output path:

```powershell
node tools/package_release.js --template C:\Users\dudie\Downloads\CrabInvSync-master.zip --out dist\CrabRuntimeProbe-ue4ss.zip
```

The ZIP root contains UE4SS runtime files and `Mods/`. The generated
`Mods/mods.txt` enables only UE4SS support mods and `CrabRuntimeProbe`.
CrabRuntimeProbe remains observe-mode by default; generated objectdump
candidates are documentation only and do not run automatically.

## Docs generation

The object dump only proves a symbol exists. It does not prove that reading or
writing it is safe at runtime.

Place Crab Champions UE4SS object dump files under `objectdump/`. The dump may
be split across many files; include every part before generating docs. Supported
input names are `*.txt`, `*.part*`, and `*.md`. The parser intentionally ignores
only `objectdump/README.md` and the generated `objectdump/objectdump_index.json`.

Objectdump workflow:

1. Copy every objectdump part into `objectdump/`.
2. Run `node tools/parse_objectdump.js`.
3. Open `docs/OBJECTDUMP_INDEX.md` and verify `All discovered dump parts scanned: yes`.
4. Run `node tools/generate_probe_candidates.js`.
5. Review `docs/PROBE_CANDIDATES.md`; generated candidates are documentation only.
6. Run `node tools/generate_docs.js` to regenerate both objectdump docs and candidate docs.

Runtime result workflow:

- `node tools/summarize_probe_results.js --results <path> [--results <another.jsonl>] [--ue4ss-log <path>]`
- The summarizer writes `docs/PROBE_RESULTS.md`, `docs/SAFE_ACCESS_MATRIX.md`, and `docs/CRASH_PHASE_SUMMARY.md`.

Interpretation rules:

- `objectdump discovered` means the symbol exists in static dump data.
- `runtime confirmed` remains false until ProbeRunner results prove a specific access path.
- Deep inventory, InventoryInfo, health, write, and RPC candidates stay disabled unless a later explicit runtime research pass enables the relevant safety gate.

## Crash collection

After a crash collect:

- `UE4SS.log`
- latest probe `.jsonl`
- active `config.txt`

`tools/summarize_probe_results.js` infers `CRASH_SUSPECT` from final unmatched breadcrumb.
