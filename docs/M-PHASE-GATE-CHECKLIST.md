# M-Phase Gate Checklist — 2026-07-19

## Blockers (must fix before any M-phase work)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 1 | `uom_mode_detect()` is a stub at `scripts/uom-lib.sh:306` — solo/dual mode detection never implemented | PRE-M-PHASE-AUDIT §2 | medium | standalone |
| 2 | `SESSION-RESUME-2026-07-18.md` references wrong branch and lists PHASE13-17 as "pending" | SESSION-RESUME L3, L167-175 | trivial | standalone |
| 3 | `ROADMAP.md` shows stale HEAD/branch, PHASE13-17 listed "pending" (all complete) | ROADMAP L5-8, L87 | trivial | standalone |
| 4 | No shellcheck pass on `scripts/*.sh tools/*.sh` before merge — risk of latent bugs | PRE-M-PHASE-AUDIT §3 | medium | standalone |
| 5 | **PHONE BOOTSTRAP RELEASE GATE**: Public one-click installer must pass static, simulated, same-phone shadow, and immutable-URL tests before M-phase work | URGENT RELEASE GATE 2026-07-19 | large | Blocks 0-8 of release gate |

## Recommended (fix soon, not blocking)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 6 | Queue sync race — no-sync prevents retry across nodes | BURNIN-SMOKE-REPORT | medium | standalone |
| 7 | Guest verifier process exited after 2 tasks — root cause unknown | BURNIN-SMOKE-REPORT | medium | investigation |
| 8 | Duplicate lib functions: `uom-lib.sh` vs `tools/uom-state-lib.sh` overlap | PRE-M-PHASE-AUDIT §3 | medium | standalone |
| 9 | Tool overlap: `tools/uom-sync-loop.sh` (old) vs `tools/uom-smoke-sync.sh` (new) | PRE-M-PHASE-AUDIT §6 | small | standalone |
| 10 | Duplicate gateway detection: `uom-net-detect.sh` and `uom-ip-discover.sh` | NETWORK-AUTOSWITCH-AUDIT.md:79 | small | standalone |
| 11 | `docs/PHONE-SETUP.md` lists stale known issues | PHONE-SETUP.md:153-158 | small | standalone |
| 12 | `docs/SYNC-ARCHITECTURE.md` — queue.json stale runtime changes | SYNC-ARCHITECTURE.md:56-60 | small | standalone |
| 13 | ~30% of commits are docs-only — consider squashing | PRE-M-PHASE-AUDIT §6 | trivial | standalone |
| 14 | `docs/README-CONFLICT-ANALYSIS.md` stale Phase 10-13 references | TODO inventory L17 | small | standalone |
| 15 | 41 commits / 125 files / +10145 lines on burn-in branch | PRE-M-PHASE-AUDIT §6 | medium | merge plan |

## Deferred (acknowledged, intentionally postponed)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 16 | PHASE17.9 8-hour burn-in | BURNIN-SMOKE-REPORT | large | standalone |
| 17 | Free tier LLM output quality (bad shebangs, dryrun FAILs) | PRE-M-PHASE-AUDIT §2 | — | accepted |
| 18 | Merge `burnin/dual-agent-20260718` → `main` | PHASE17-MERGE-PLAN.md | large | items 1,4,15 |
| 19 | Deploy updated scripts to phone/guest | SESSION-RESUME-2026-07-18 L174 | medium | item 18 |

## Unknown (needs investigation)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 20 | Guest verifier instability — PID 5354 exited after 2 tasks | BURNIN-SMOKE-REPORT | medium | crash logs |
| 21 | Phone-side dryrun verification — `scripts/uom-dryrun.sh` never tested | SESSION-RESUME-2026-07-18 L175 | small | phone SSH |
| 22 | ShellCheck results — not run, unknown warnings/errors | PRE-M-PHASE-AUDIT §3 | small | shellcheck |
| 23 | Sync race window — how often are retries lost | BURNIN-SMOKE-REPORT | medium | instrumentation |
| 24 | QEMU guest `/` at 77% disk — could cause verifier crashes | df output | small | disk check |
