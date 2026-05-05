# Runtime Contexts

Conservative context labels used by probe results:

- `menu`: no valid `CrabPC` during early ticks.
- `lobby`: valid `CrabPC`, no valid `PlayerState`.
- `solo`: valid `CrabPC` and valid local `PlayerState`.
  - Current limitation: this detector cannot distinguish true solo from multiplayer host or host-like local contexts.
  - The emitted role `solo-or-host` means `local-player-present`; it is not proof that the run was solo.
- `unknown`: insufficient passive evidence.
- `traveling`, `unstable`, `dead-or-respawning`: lifecycle guard states.

Observe mode samples these labels only after `startupWarmupTicks`, and only on
`observeIntervalTicks`.
