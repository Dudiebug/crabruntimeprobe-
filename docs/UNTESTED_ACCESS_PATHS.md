# Untested Access Paths

The following areas remain UNTESTED or UNSAFE_DISABLED unless explicit runtime evidence is imported later.

| Symbol | Access method | Runtime status | Notes |
|---|---|---|---|
| `CrabPS.InventoryInfo` | GetPropertyValue | UNTESTED | InventoryInfo probes are disabled. |
| `CrabPS.InventoryInfo` | DirectField | UNTESTED | Direct field access is a separate risk class. |
| `CrabInventoryInfo.*` | array traversal | UNTESTED | Deep arrays are disabled. |
| `CrabHC.Health` | read | UNTESTED | Health probes are disabled. |
| `CrabHC.HealthInfo.*` | write | UNTESTED | Health writes are disabled. |
| `CrabHC.PlayerOwnership` | discovery | UNTESTED | Player-owned CrabHC discovery is not proven yet; unscoped FindFirstOf.CrabHC is ambiguous. |
| `CrabPS.HealthInfo.*` | write | UNTESTED | Health writes are disabled. |
| `CrabPS.HealthInfo.*` | joined-client | UNTESTED | Joined-client local PlayerState health visibility has not been separately imported. |
| `CrabPS.HealthInfo.*` | multiplayer watch | UNTESTED | Vanilla multiplayer evidence is local PlayerState health visibility only; it does not define shared/pooled health behavior. |
| `CrabHC.HealthInfo.*` | multiplayer | UNTESTED | Player-owned CrabHC discovery in multiplayer is untested; do not use it to infer vanilla or CrabInvSync health behavior. |
| `GameState.PlayerArray` | identity roster | UNTESTED | Roster reads require the explicit multiplayer-roster-read phase and must remain capped/redacted; latest evidence returned nil instead of a Lua table. |
| `CrabGS` | identity source candidate | UNTESTED | CrabGS availability is checked only in multiplayer-roster-read and must not recurse through arbitrary fields. |
| `FindAllOf(PlayerState,CrabPS)` | identity roster candidates | UNTESTED | Capped PlayerState-like discovery is gated by allowIdentityProbes and emits only redacted/fingerprinted identity values. |
| `FindAllOf(PlayerController,CrabPC).PlayerState` | identity controller candidates | UNTESTED | Capped controller discovery reads only PlayerState from valid controllers. |
| `FindAllOf(PlayerState,CrabPS)` | resource visibility candidates | UNTESTED | Capped resource visibility discovery is gated by allowResourceVisibilityProbes and reads only explicitly named PlayerState fields. |
| `PlayerState.UniqueId` | identity | UNTESTED | Stable IDs must be fingerprinted unless allowRawIdentityEvidence is explicitly enabled. |
| `GameplayState.*` | write | UNSAFE_DISABLED | Writes are disabled. |
| `RPC.*` | rpc | UNSAFE_DISABLED | RPC probes are disabled. |
