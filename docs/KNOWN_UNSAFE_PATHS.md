# Known Unsafe Paths

- HUD ReceiveDrawHUD tick hook is known unsafe in current Crab Champions/UE4SS evidence and remains blocked by default.
- `FindFirstOf.CrabHC` is not a safe player-health source. It is unscoped and session `20260505T002614Z` found `BP_Destructible_ChaoticBarrel10.HC`, a destructible/barrel component.
- Do not use unscoped `CrabHC` discovery, item arrays, `InventoryInfo`, writes, RPCs, or HUD hooks for `health-playerstate-watch`.
- Do not publish raw platform/Steam identity values from roster evidence; keep `allowRawIdentityEvidence = false` unless private evidence capture is explicitly requested.
