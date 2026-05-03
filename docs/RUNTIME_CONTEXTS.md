# Runtime Contexts

Conservative context labels used by probe results:

- `menu`: no valid `CrabPC` during early ticks.
- `lobby`: valid `CrabPC`, no valid `PlayerState`.
- `solo`: valid `CrabPC` and valid `PlayerState`; role is `solo-or-host`.
- `unknown`: insufficient passive evidence.
- `traveling`, `unstable`, `dead-or-respawning`: lifecycle guard states.

Observe mode samples these labels only after `startupWarmupTicks`, and only on
`observeIntervalTicks`.
