# WATCHDOG AUDIT — 2026-07-18 (Phase 1)

## Summary

- **18 watchdog/resilience files** in repo, 3,470 lines total
- **7 distinct watchdog scripts** — each monitors something different
- **1 clear duplicate:** `bin/uom-tmux-guardian.sh` duplicates `orchestrators/uom-tmux-watchdog.sh`
- **1 deprecated:** `scripts/uom-final-fix.sh`
- **CRITICAL:** QEMU watchdog deployed but NOT auto-started
- **CRITICAL:** tmux watchdog crashes after boot, no sessions persist
- **Phone SHA diverged:** `uom-tmux-watchdog.sh` (phone: `17862c3` vs repo: `b726266`)

## Watchdog Inventory

| # | Script | Lines | Purpose | Status |
|---|--------|-------|---------|--------|
| 1 | `scripts/uom-qemu-watchdog.sh` | 184 | QEMU health P1-P10 | KEEP |
| 2 | `orchestrators/uom-watchdog.sh` | 364 | Laptop reachability + phone takeover | KEEP |
| 3 | `orchestrators/uom-tmux-watchdog.sh` | 320 | Tmux session watchdog | KEEP (absorb #6) |
| 4 | `bin/omni-healer` | 65 | Laptop self-healing daemon | KEEP |
| 5 | `bin/uom-tmux-watchdog.sh` | 2 | Wrapper to orchestrators/ | KEEP |
| 6 | `bin/uom-tmux-guardian.sh` | 181 | Tmux guardian (DUP of #3) | MERGE → DELETE |
| 7 | `scripts/uom-final-fix.sh` | 107 | Legacy fix (DEPRECATED) | DELETE |
| 8 | `orchestrators/uom-port-guardian.sh` | 303 | Port drift detection | KEEP |
| 9 | `orchestrators/uom-solo-orchestrator.sh` | 244 | Phone-only task executor | KEEP |
| 10 | `tools/uom-port-watch.sh` | 134 | Port probe primitives | KEEP |
| 11 | `tools/uom-orch-phone.sh` | 270 | Phone orchestrator | KEEP |
| 12 | `orchestrators/uom-reconcile.sh` | 855 | Full reconciliation | KEEP |

## Healer Subsystem

| Script | Lines | Purpose |
|--------|-------|---------|
| `src/healer/common.sh` | 68 | Healer config + helpers |
| `src/healer/services.sh` | 23 | Service watchdog loop |
| `src/healer/gpu.sh` | 30 | GPU state watchdog |
| `src/healer/storage.sh` | 53 | Storage I/O watcher |
| `src/deploy/healer_install.sh` | 167 | Healer installer (5 init systems) |

## Duplicate Map

| File A | File B | Overlap | Action |
|--------|--------|---------|--------|
| `orchestrators/uom-tmux-watchdog.sh` | `bin/uom-tmux-guardian.sh` | Both manage `uom` tmux session | MERGE guardian layout into watchdog, DELETE guardian |

## Phone vs Repo Divergence

| Script | Repo SHA | Phone SHA | Status |
|--------|----------|-----------|--------|
| `uom-qemu-watchdog.sh` | `690c454` | `690c454` | MATCH |
| `uom-tmux-watchdog.sh` | `b726266` | `17862c3` | **DIVERGED** |
| `uom-lib.sh` | `c6361c2` | `c6361c2` | MATCH |

## Gap Analysis for Master Watchdog (Phase 2)

| Gap | Severity | Current State |
|-----|----------|---------------|
| No unified watchdog process | CRITICAL | 7 scripts running independently |
| QEMU watchdog not auto-started | CRITICAL | Deployed but never launched |
| tmux watchdog crashes after boot | HIGH | Boot script starts it but it dies |
| No cross-watchdog signaling | HIGH | Each watchdog is isolated |
| No unified health dashboard | HIGH | 6+ log files in different formats |
| No watchdog self-test | MEDIUM | Only temp `watchdog-sim.sh` on phone |

## Phone Boot Script

`~/.termux/boot/start-uom.sh` starts:
- sshd (port 8022)
- reverse SSH tunnel
- tmux-watchdog (but it crashes)
- phone orchestrator

Does NOT start:
- QEMU watchdog
- omni-healer
- port-guardian
- wake-lock

## Phone Process State (LIVE)

| Component | Running? |
|-----------|----------|
| QEMU | YES (PID 30769) |
| tmux sessions | `uom-qemu-host` only |
| tmux-watchdog | NO |
| QEMU watchdog | NO |
| omni-healer | NO |
| port-guardian | NO |

<!-- last-sync: 2026-07-18T20:55:00+05:30 -->
