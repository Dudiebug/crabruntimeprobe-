# Codex guardrails for CrabRuntimeProbe

- Do not turn this into CrabInvSync.
- Do not add gameplay sync.
- No write probes by default.
- No mutating RPC calls by default.
- Every risky operation requires breadcrumbs before and after.
- Generated docs must distinguish:
  - "object dump says this exists"
  - "runtime probe confirmed this is safe"
