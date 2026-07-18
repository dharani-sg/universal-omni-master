# Dual-Orchestrator Trace — 2026-07-18

## Architecture

```
PHONE (Termux/Mi 8)                    LAPTOP (Alpine Linux)
┌─────────────────────┐                ┌──────────────────────────┐
│ generator           │  SSH (8022)    │ verifier                 │
│ uom-generator.sh    │◄──────────────►│ uom-verifier.sh          │
│ or                  │                │                          │
│ uom-phone-gen-loop  │                │ reconciler               │
│ (PHASE14)           │                │ uom-reconcile.sh         │
│                     │                │                          │
│ queue.json          │  rsync sync    │ queue.json               │
│ generated/          │◄──────────────►│ generated/               │
│ feedback/           │                │ verified/                │
└─────────────────────┘                │ feedback/                │
                                       └──────────────────────────┘
```

## Data Flow

### 1. Generator (Window A) — Phone side
- Reads `.uom-agent/queue.json` for `pending` tasks sorted by priority.
- Picks the highest-priority pending task.
- Calls LLM via:
  - Local `opencode` CLI (laptop) OR
  - `scripts/uom-llm-remote.sh` (phone → laptop SSH) OR
  - Stub fallback.
- Writes output to `.uom-agent/generated/{task_id}.sh`.
- Creates `.ready` marker JSON with task_id, model, timestamp.
- Marks task `in_progress` in queue.json.
- **Flaw (pre-A9 fix):** No state lease check, no LLM timeout, mutates
  queue.json directly without consulting state.json `writer_role`.

### 2. Verifier (Window B) — Laptop side
- Polls `.uom-agent/generated/*.ready` every 5s.
- For each `.ready` file found:
  - Runs syntax check (`sh -n`).
  - Runs policy check (no curl-pipe-sh, no sudo, no 18022, etc.).
  - Runs dry-run (`scripts/uom-dryrun.sh`).
  - Writes `.uom-agent/verified/{task_id}.result` JSON.
  - Updates queue.json status to `verified` or `failed`.
  - Moves `.ready` → `.done`.
  - For FAIL results, writes `feedback/{task_id}.json`.

### 3. Reconciler — Laptop side (orchestrators/uom-reconcile.sh)
6-step process:
1. **Step 0:** Pre-flight checks (sshd, jq, opencode, DNS, network).
2. **Step 1:** Tmux isolation (4 windows: orchestrator, generator, verifier, status).
3. **Step 2:** Cloud bootstrap & dynamic model selection from 4-model pool.
4. **Step 3:** Network discovery & tunnel orchestration (dynamic port 31400-31499).
5. **Step 4:** Port guardian initialization (host hints for phone/laptop).
6. **Step 5:** Dual-agent Zen Loop — launches generator + verifier in tmux.
7. **Step 6:** Supervisor & final verification (process, tunnel, queue health).

### 4. Sync (PHASE15)
- `tools/uom-sync-loop.sh` (planned): rsync-based bidirectional sync.
- Phone pushes `generated/` to laptop.
- Laptop pushes `verified/` and `feedback/` to phone.

### 5. Feedback Protocol (PHASE13.D)
- Verifier writes `feedback/{task_id}.json` for FAIL results.
- Generator reads feedback before retrying a failed task.
- Feedback format:
  ```json
  {
    "task_id": "M33",
    "feedback_for": "generator",
    "result": "FAIL",
    "issues": "syntax:bad-shebang",
    "suggestion": "Fix the reported issues and regenerate"
  }
  ```

## Key Files

| Path | Role |
|------|------|
| `scripts/uom-generator.sh` | Phone-side generator agent (old) |
| `scripts/uom-verifier.sh` | Laptop-side verifier agent |
| `scripts/uom-llm-remote.sh` | SSH-based remote LLM call |
| `scripts/uom-dryrun.sh` | Integration test suite |
| `orchestrators/uom-reconcile.sh` | 6-step reconciler/orchestrator |
| `orchestrators/uom-solo-orchestrator.sh` | Phone-solo mode orchestrator |
| `tools/uom-state-lib.sh` | State library (v2) |
| `bin/uom-ssh-phone.sh` | SSH wrapper with drift-tolerant discovery |

## Critical Paths (Blocking)

1. **Generator bypasses state lease** — reads/writes queue.json directly.
   Must check `state.json writer_role` before picking tasks.
   *Fix: PHASE13.C*

2. **Generator has no LLM timeout** — blocks forever on `opencode`.
   Must use `timeout` with 120s limit.
   *Fix: PHASE13.C*

3. **State.json v1+v2 mixed** — `.uom-agent/state.json` has both schema
   versions. Must migrate fully to v2.
   *Fix: PHASE13.C*

4. **Missing queue tool** — `tools/uom-queue.sh` doesn't exist. Queue
   operations are ad-hoc inline jq calls.
   *Fix: PHASE13.C*

## Deployment Topology (Current)

- **Laptop:** `192.168.40.90/24` — runs verifier, reconciler, SSH client
- **Phone:** `192.168.40.207` (gateway/hotspot) — runs generator, SSH server :8022
- **Guest:** `127.0.0.1:2222` (inside phone QEMU) — runs Alpine for testing
- **Network:** No VPN/mesh, no Tailscale/ZeroTier/WireGuard
- **Auth:** `id_ed25519_phone` key, no API keys (free tier)
