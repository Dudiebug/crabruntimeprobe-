# Untested Access Paths

The following areas remain UNTESTED or UNSAFE_DISABLED unless explicit runtime evidence is imported later.

| Symbol | Access method | Runtime status | Notes |
|---|---|---|---|
| `CrabPS.InventoryInfo` | GetPropertyValue | UNTESTED | InventoryInfo probes are disabled. |
| `CrabPS.InventoryInfo` | DirectField | UNTESTED | Direct field access is a separate risk class. |
| `CrabInventoryInfo.*` | array traversal | UNTESTED | Deep arrays are disabled. |
| `CrabHC.Health` | read | UNTESTED | Health probes are disabled. |
| `CrabHC.HealthInfo.*` | write | UNTESTED | Health writes are disabled. |
| `CrabPS.HealthInfo.*` | write | UNTESTED | Health writes are disabled. |
| `CrabPS.HealthInfo.*` | joined-client | UNTESTED | Multiplayer/joined-client health evidence does not exist yet. |
| `CrabHC.HealthInfo.*` | multiplayer | UNTESTED | Multiplayer max-health math is untested. |
| `GameplayState.*` | write | UNSAFE_DISABLED | Writes are disabled. |
| `RPC.*` | rpc | UNSAFE_DISABLED | RPC probes are disabled. |
