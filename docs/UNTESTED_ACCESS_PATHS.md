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
| `CrabPS.HealthInfo.*` | joined-client | UNTESTED | Multiplayer/joined-client health evidence does not exist yet. |
| `CrabPS.HealthInfo.*` | multiplayer watch | UNTESTED | Multiplayer health scaling remains unproven until health-playerstate-watch evidence exists from multiplayer scenarios. |
| `CrabHC.HealthInfo.*` | multiplayer | UNTESTED | Multiplayer max-health math is untested. |
| `GameState.PlayerArray` | identity roster | UNTESTED | Roster reads require the explicit multiplayer-roster-read phase and must remain capped/redacted. |
| `PlayerState.UniqueId` | identity | UNTESTED | Stable IDs must be fingerprinted unless allowRawIdentityEvidence is explicitly enabled. |
| `GameplayState.*` | write | UNSAFE_DISABLED | Writes are disabled. |
| `RPC.*` | rpc | UNSAFE_DISABLED | RPC probes are disabled. |
