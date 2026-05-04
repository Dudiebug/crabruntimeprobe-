# Codex Guardrails for CrabRuntimeProbe

This repository exists to build **CrabRuntimeProbe**, a standalone UE4SS Lua diagnostic/research mod.

## Non-goals

- Do **not** turn this into CrabInvSync.
- Do **not** add gameplay synchronization.
- Do **not** implement shared inventory logic.
- Do **not** add write probes.
- Do **not** call mutating RPCs.
- Do **not** add deep inventory probes until runtime safety is established.

## Probe safety requirements

- No write probes.
- No mutating RPC calls.
- Every risky operation must emit a breadcrumb **before** and **after** the operation.
- Use paced probing and context gates; `pcall` alone is not considered sufficient crash protection.

## Documentation requirements

Generated docs must clearly distinguish:

1. **Object dump presence** ("this symbol appears in dumps"), and
2. **Runtime validation** ("this operation was probed and observed safe/unsafe/unknown at runtime").
