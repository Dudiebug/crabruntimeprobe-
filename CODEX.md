# Codex guardrails for CrabRuntimeProbe

- Do **not** turn this project into CrabInvSync.
- Do **not** add gameplay sync or shared inventory behavior.
- Keep write probes and RPC probes disabled by default.
- Every risky runtime operation must emit breadcrumb logs before and after.
- Generated docs must clearly distinguish:
  - "object dump says this exists"
  - "runtime probe confirmed this is safe"
