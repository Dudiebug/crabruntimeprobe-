# Known Unsafe Paths

- HUD ReceiveDrawHUD tick hook is known unsafe in current Crab Champions/UE4SS evidence and remains blocked by default.
- `FindFirstOf.CrabHC` is not a safe player-health source. It is unscoped and session `20260505T002614Z` found `BP_Destructible_ChaoticBarrel10.HC`, a destructible/barrel component.
