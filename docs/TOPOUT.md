# Session Topology & State — Universal Omni Master (UOM)

## Current Session: PHASE17 — Distributed Smoke Test

**Session started:** 2026-07-19T03:29:11Z  
**Session ended:** 2026-07-19T09:16:00Z  
**Branch:** burnin/dual-agent-20260718 (HEAD e072fab)  
**Three-way aligned at HEAD**

## Topology

```
LAPTOP  ◄── ssh :8022 ──►  PHONE  ◄── ssh :2222 ──►  GUEST (QEMU)
alpine@x86_64              MI 8 aarch64               Alpine 3.21.7 aarch64
192.168.40.90/24           192.168.40.207/24           127.0.0.1 (phone-local)
Generator + Feedback        Sync relay                  Verifier only
```

### Options considered (PHASE17)
- **Chosen (A):** Generator on laptop, verifier on guest, feedback on laptop
- **Rejected (B):** Verifier on phone (no QEMU) — not viable, phone lacks dry-run env
- **Rejected (C):** All on guest — guest has no `node`/`npm` (doas requires TTY)

## Component roles

| Node | Role | Processes |
|---|---|---|
| Laptop | Generator + Feedback aggregator + Sync master | `uom-generator.sh`, `uom-feedback-aggregator.sh`, `uom-smoke-sync.sh` |
| Phone | SSH relay between laptop and guest | OpenSSH `sshd :8022` → forward to guest `:2222` |
| Guest (QEMU) | Verifier only | `scripts/uom-verifier.sh` |

## Artifact flow

```
Generator ──► generated/ ──sync──► Guest generated/
                                         │
                                   Verifier reads
                                         │
                                   writes .result to verified/
                                         │
                                   writes retry to feedback/
                                         │
Guest verified/ ──sync──► Laptop verified/
Guest feedback/  ──sync──► Laptop feedback/
                                   │
                           Feedback aggregator
                                   │
                           writes to feedback/ (for generator)
```

**Key design decision:** `queue.json` is NOT synced between nodes to avoid races.

## Deployment model

- **Laptop:** Native git clone (this workspace)
- **Phone:** Termux git clone + SSH daemon
- **Guest:** Extracted tree (no `.git`), accessed via phone SSH tunnel

## Infrastructure constraints

| Constraint | Impact |
|---|---|
| Free tier LLM (north-mini-code-free) | Hard ceiling 9 LLM calls/session |
| Phone hotspot NAT | Laptop ↔ phone only; no internet on guest |
| No node/npm on guest | Generator cannot run on guest |
| QEMU TCG (no KVM) | Slow verification (~0.1x native) |

## PHASE17 Outcomes

- [x] 3-task distributed smoke test executed
- [x] Generator produced LLM output for all 3 tasks
- [x] 3-node sync relay proven (laptop → phone → guest)
- [x] Verifier processed 2 tasks (FAIL with dryrun issues)
- [x] Retry path triggered (SMOKE-001: → Retry 1/3)
- [x] Quota counter working (3/9 calls used)
- [x] Zero 429 rate-limit events
- [ ] 8-hour PHASE17.9 burn-in **DEFERRED**
- [ ] SMOKE-002 retry trajectory **NOT PROVEN** (queue sync disabled)
- [ ] Supervisor checkpoint reports **NOT RUN** (phone tmux)

## Next Steps

1. Run `shellcheck` on all scripts before merge
2. Resolve 5-8 conflicts with `main` branch
3. File PHASE17.9 burn-in as future session task
4. Deploy to phone + guest after merge
