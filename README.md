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

Use the install script from the real Git checkout. Do not drag a random local
folder named `CrabRuntimeProbe` into the game; copied folders can be stale and
may be missing safety defaults such as `allowHudTickHook = false`.

The Crab Champions Win64 game bin path is usually:

```text
C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64
```

Preferred install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-client-to-game.ps1 "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
```

Preferred export for manual copying:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\export-client-folder.ps1
```

Verification:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-installed-client.ps1 "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
```

`allowHudTickHook` must remain `false` unless you are intentionally testing the
unsafe HUD fallback that crashed immediately in this Crab Champions/UE4SS setup.
The source default remains `tickDriver = none`; the first confirmed safe
diagnostic tick driver for this UE4SS/Crab Champions setup is `executeDelay`.

## Minimal user workflow

1. Paste Codex prompts.
2. Pull latest if Codex tells you a fix was committed:

```powershell
git checkout main
git pull origin main
```

3. Run one quick smoke prepare script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-smoke-prepare.ps1
```

4. Launch Crab Champions, sit at the menu for 20 to 30 seconds, then quit.
5. Run one quick smoke collect script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-smoke-collect.ps1
```

6. Paste
`Mods\CrabRuntimeProbe\Scripts\diagnostic_summary.txt` back to ChatGPT/Codex.

Only after the smoke test passes, test one isolated tick driver:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-tickdriver-prepare.ps1 -TickDriver executeDelay
```

Launch Crab Champions, sit at the menu for 20 to 30 seconds, then quit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-tickdriver-collect.ps1
```

For the next safe gameplay observe pass after `executeDelay` is confirmed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-gameplay-observe-prepare.ps1
```

Launch Crab Champions, start a solo run or host lobby, stay alive/in world for
30 to 60 seconds, quit, then collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-gameplay-observe-collect.ps1
```

After gameplay observe passes, run the next read-only equipment property phase:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-equipment-property-prepare.ps1
```

Launch Crab Champions, start a solo run, stay in-world 30 to 60 seconds, quit,
then collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-equipment-property-collect.ps1
```

`equipment-property-read` is still read-only. It reads only `WeaponDA`,
`AbilityDA`, and `MeleeDA` from `CrabPS` using `GetPropertyValue`. It does not
read item arrays, does not read `InventoryInfo`, does not read health, does not
write anything, and does not run RPC probes. Direct field equipment probes are
intentionally separate in `equipment-direct-field-read`.

## Evidence-driven documentation pipeline

RuntimeProbe writes three compact runtime artifacts during tests:

- `probe_results_<session>.jsonl`
- `access_evidence_<session>.jsonl`
- `session_manifest_<session>.json`

The UE4SS Lua mod only writes append-only evidence and session context. It does
not generate the full GitHub Wiki in-game. Repo tools import copied game
evidence, update docs under `docs/`, and stage wiki pages under `dist/wiki/`.
GitHub Wiki publishing comes later.

After a play/test pass, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\import-latest-runtime-evidence.ps1
```

This imports the latest game evidence into `evidence/runtime/`, regenerates the
safe access docs, and stages generated wiki Markdown. Repo docs remain the source
of truth; staged wiki files are derived output.

After `equipment-property-read` passes, run the next read-only health baseline
phase:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-baseline-prepare.ps1
```

Launch Crab Champions, start a solo run, stay in-world 30 to 60 seconds, quit,
then collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-baseline-collect.ps1
```

Then import the resulting evidence and rebuild docs/wiki staging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\import-latest-runtime-evidence.ps1
```

`health-baseline-read` is read-only. It exists to prove health/max-health fields
for CrabInvSync v2 research without writing health, calling health RPCs, reading
deep arrays, or touching `InventoryInfo`. The first health baseline evidence
showed that unscoped `FindFirstOf.CrabHC` can point at non-player health
components: session `20260505T002614Z` found
`BP_Destructible_ChaoticBarrel10.HC`. Do not use unscoped `CrabHC` as the
CrabInvSync v2 player health source.

The safer player-scoped health path is currently `CrabPC -> PlayerState ->
CrabPS`. In solo evidence, `CrabPS.HealthInfo.CurrentHealth`,
`CrabPS.HealthInfo.CurrentMaxHealth`, and `CrabPS.BaseMaxHealth` returned
`250.0`, while `CrabPS.MaxHealthMultiplier` returned `1.0`. This supports a
solo base-health value of 250, but it does not prove multiplayer max-health math
yet; the 250 HP per player theory still needs multiplayer evidence.

After the broad baseline phase, prefer the player-state-only health phase:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-playerstate-prepare.ps1
```

Launch Crab Champions, start a solo run, stay in-world 30 to 60 seconds, quit,
then collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-playerstate-collect.ps1
```

Then import the resulting evidence and rebuild docs/wiki staging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\import-latest-runtime-evidence.ps1
```

After the single player-state snapshot, run the read-only health watch phase to
capture time-series evidence from the same safe path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-playerstate-watch-prepare.ps1
```

User run:

1. Launch Crab Champions.
2. Start a solo run.
3. Stay in-world for 60 to 120 seconds.
4. If a max-health-changing pickup/perk naturally appears, pick it up.
5. Otherwise do not force it.
6. Quit.

Then collect and validate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\quick-health-playerstate-watch-collect.ps1
```

Then import the resulting evidence and rebuild docs/wiki staging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\import-latest-runtime-evidence.ps1
```

`health-playerstate-watch` repeatedly emits one combined
`Health.PlayerState.Sample` row with `CurrentHealth`, `CurrentMaxHealth`,
`BaseMaxHealth`, and `MaxHealthMultiplier`. It exists to gather time-series
evidence before any CrabInvSync v2 health math is designed. It is read-only,
uses `CrabPC -> PlayerState -> CrabPS -> HealthInfo`, avoids `CrabHC`, avoids
item arrays and `InventoryInfo`, and does not write or call RPCs. Multiplayer
health scaling remains unproven until multiplayer watch evidence exists; do not
infer production health math from one static solo snapshot.

Player-owned `CrabHC` discovery is a separate research phase. The
`health-hc-discovery-read` probe set currently records `FindAllOf` availability
only; capped candidate traversal and ownership linkage stay deferred until that
path is reviewed as its own explicit read-only test.

The quick scripts use the default Steam path:

```text
C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64
```

For a non-default install path, use the full diagnostic cycle script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-local-diagnostic-cycle.ps1 -GameBin "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64" -PrepareSmoke
```

After launching and quitting:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-local-diagnostic-cycle.ps1 -GameBin "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64" -CollectSmoke
```

## Quick local test install

Install the latest client mod directly into a local Crab Champions UE4SS
installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-client-to-game.ps1 "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
```

Verify the installed files, `Mods\mods.txt`, and safe observe defaults:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-installed-client.ps1 "C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64"
```

During CrabRuntimeProbe testing, disable `CrabInventorySync` so the probe log is
easy to reason about. The install helper does not delete or disable other mods.

If no JSONL appears, check `UE4SS.log` for `CrabRuntimeProbe`, confirm it has
`tick source registered`, then temporarily set `debugTickHeartbeat = true` and
`debugWriterSelfTest = true`. Confirm `Mods\mods.txt` has
`CrabRuntimeProbe : 1`, check
`Mods\CrabRuntimeProbe\Scripts\results\`, and then check the fallback
`Mods\CrabRuntimeProbe\Scripts\`. If the log says
`tick source registered: HUD ReceiveDrawHUD`, the config is unsafe for normal
Crab Champions testing; set `allowHudTickHook = false`.

## First safe run

Use:

- `mode = observe`
- `tickDriver = none`
- `observeIntervalTicks = 10`
- `allowHudTickHook = false`
- `probeSet = shallow-core`
- `allowDeepArrayProbes = false`
- `allowInventoryInfoProbes = false`
- `allowHealthProbes = false`
- `allowIdentityProbes = false`
- `allowRawIdentityEvidence = false`
- `allowResourceVisibilityProbes = false`
- `allowInventoryArrayShallowProbes = false`
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

## Troubleshooting: no probe_results JSONL appears

Check `UE4SS.log` for `tick source registered`. A normal startup should print
the config path, mode, primary result path, fallback result path, and selected
tick source. The HUD `ReceiveDrawHUD` hook is disabled by default because it
caused immediate startup crashes in Crab Champions. Leave
`allowHudTickHook = false` unless you are intentionally debugging that hook.

For a diagnostic observe-mode run, temporarily set:

- `mode = observe`
- `writeJsonlResults = true`
- `debugTickHeartbeat = true`
- `debugWriterSelfTest = true`
- `allowHudTickHook = false`

Then launch the game and check for `tick heartbeat` lines every 100 ticks. The
writer self-test should create one `Debug.WriterSelfTest` JSONL row without
touching UE objects.

Check both result locations:

- Primary: `Mods/CrabRuntimeProbe/Scripts/results/probe_results_*.jsonl`
- Fallback: `Mods/CrabRuntimeProbe/Scripts/probe_results_*.jsonl`

If the primary directory is unavailable, `UE4SS.log` should include
`primary result path unavailable; using fallback`. If neither path can be
written, it should include `ERROR: result write failed for primary and fallback`.
Keep `mode = observe` for this diagnostic pass so active probes stay disabled.
If no JSONL appears, check the tick source line in `UE4SS.log`; heartbeat lines
confirm that the selected scheduler is actually firing.

By default `tickDriver = none`, so the first smoke run should not register any
tick source. Set exactly one tick driver only for an isolated follow-up run:
`executeDelay` is the first confirmed safe diagnostic tick driver. Do not test
`registerTick`, `loopAsync`, or `hud` by default. The `hud` driver remains
blocked by the local helper because `allowHudTickHook = false` is the safe
default, and HUD `ReceiveDrawHUD` must remain disabled unless intentionally
testing that known-unsafe path.

## Release packaging

CrabRuntimeProbe includes a source-visible UE4SS bundle template under
`client/`. The UE4SS runtime files, UE4SS settings, UE4SS support mods, and
UE4SS license were copied from a local CrabInvSync checkout/ZIP and are kept in
source so reviewers can inspect the exact support files used by packaging.

The packager does not copy CrabInvSync gameplay code, server files, objectdump
files, runtime logs/output, `.git`, or `node_modules`. The bundle is meant to be
extracted into:

```text
Crab Champions\CrabChampions\Binaries\Win64\
```

Recommended PowerShell workflow from the provided local ZIP:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-ue4ss-bundle.ps1 -CrabInvSyncRoot "C:\Users\dudie\Downloads\CrabInvSync-master.zip" -Version "0.1.0"
```

Build a staging folder without creating a ZIP:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-ue4ss-bundle.ps1 -CrabInvSyncRoot "C:\Users\dudie\Downloads\CrabInvSync-master.zip" -Version "0.1.0" -NoZip
```

Verify an existing staging folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-ue4ss-bundle.ps1 "dist\CrabRuntimeProbe-v0.1.0-UE4SS"
```

Optional Node packager:

```powershell
node tools/package_release.js --template C:\Users\dudie\Downloads\CrabInvSync-master.zip
```

## Exporting the client folder for manual testing

To export only the latest CrabRuntimeProbe client/mod files for manual testing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\export-client-folder.ps1
```

The export script writes a clean copy of the current repo's `client` folder to:

```text
dist\CrabRuntimeProbe-client
```

For a full manual UE4SS client copy, copy the contents of that folder into:

```text
C:\Program Files (x86)\Steam\steamapps\common\Crab Champions\CrabChampions\Binaries\Win64
```

For a mod-only manual copy, copy
`dist\CrabRuntimeProbe-client\Mods\CrabRuntimeProbe` into the game folder's
`Mods\CrabRuntimeProbe` path. Prefer the install script when possible because
it validates the source config, writes `Scripts\build_info.txt`, and verifies
the installed config after copying.

The bundle root contains UE4SS runtime files, `INSTALL.txt`, the
CrabRuntimeProbe README/license, and `Mods/`. The copied UE4SS support mods are:

- `client/UE4SS.dll`
- `client/dwmapi.dll`
- `client/UE4SS-settings.ini`
- `client/imgui.ini`
- `Mods/BPML_GenericFunctions`
- `Mods/BPModLoaderMod`
- `Mods/Keybinds`
- `Mods/shared`

These are UE4SS support files sourced from the CrabInvSync template, not
CrabRuntimeProbe gameplay code. The generated `Mods/mods.txt` enables only
these support mods and `CrabRuntimeProbe`. CrabRuntimeProbe remains observe-mode
by default; generated objectdump candidates are documentation only and do not
run automatically.

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
- Local inventory array visibility and remote PlayerState inventory array visibility are separate research questions. `local-inventory-array-shallow-read` only checks local `CrabPC -> PlayerState -> CrabPS` array shapes/counts and slot scalars; it does not dereference elements, read DA fields, read `InventoryInfo`, read Enhancements, write, call RPCs, use HUD hooks, or touch `CrabHC`.
- Inventory item metadata is still untested. Remote inventory array counts remain partial/unresolved in the latest resource visibility evidence, while local inventory arrays require their own imported evidence.
- Deep inventory, InventoryInfo, health, write, and RPC candidates stay disabled unless a later explicit runtime research pass enables the relevant safety gate.

## Crash collection

After a crash collect:

- `UE4SS.log`
- latest probe `.jsonl`
- active `config.txt`

`tools/summarize_probe_results.js` infers `CRASH_SUSPECT` from final unmatched breadcrumb.
