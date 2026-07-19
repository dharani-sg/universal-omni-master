# PHASE17 Distributed Smoke Test — Topology Decision

## Context

The original plan called for the generator to run on the guest (QEMU Alpine VM)
during the distributed smoke test. However, the guest lacks node/npm/opencode,
and `doas` requires a TTY which non-interactive SSH cannot provide.

## Decision: Option A — Generator on laptop, Verifier on guest

### Roles

| Component              | Node    | Rationale                                       |
|------------------------|---------|-------------------------------------------------|
| Generator (LLM)        | Laptop  | Has opencode + quota; writes to sandbox         |
| Verifier               | Guest   | No LLM needed; tests sync loop + remote exec    |
| Feedback aggregator    | Laptop  | Reads verified/ from local sandbox              |
| Supervisor             | Phone   | tmux session, monitors all nodes                |
| Sync loop              | Laptop  | Bridges laptop <-> phone <-> guest via SSH tar  |

### Data flow

```
Laptop                          Phone           Guest (Alpine)
──────────────────────────────────────────────────────────────
Generator → sandbox/generated/
    └─ sync loop ─────────────► relay ────────► sandbox/generated/
                                                    Verifier reads
                                                    Verifier writes
    ◄─ sync loop ───────────── relay ◄──────── sandbox/verified/
Feedback-agg reads verified/
Queue.json bidirectional sync (last-writer-wins)
```

### Why not the alternatives

- **Option B** (interactive SSH to install opencode on guest): Requires a
  human to sit at a terminal running `doas apk add` interactively. Blocked
  until someone can physically or via a TTY-capable SSH session do this.
- **Option C** (stub generator on guest): Introduces a fake component that
  would not test the real LLM path. Less valuable as a smoke test.

### Risk

- The sync loop uses `last-writer-wins` for queue.json. With a single task
  in flight at a time, conflict probability is near zero.
- Guest verifier must have `jq` installed (confirmed: Alpine has `jq` in
  its base install).

## Status

- [x] Decision recorded
- [ ] Smoke test env prepared (sandbox + fixtures)
- [ ] Sync loop updated for 3-node relay
- [ ] Smoke test executed
- [ ] Results documented in BURNIN-SMOKE-REPORT-YYYYMMDD.md
