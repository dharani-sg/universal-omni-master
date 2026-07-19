# M-Phase Gate Checklist — 2026-07-19

Extracted from: PRE-M-PHASE-AUDIT-20260719.md, TODO inventory,
ROADMAP.md, SESSION-RESUME-2026-07-18.md

---

## Blockers (must fix before any M-phase work)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 1 | `uom_mode_detect()` is a stub at `scripts/uom-lib.sh:306` — solo/dual mode detection never implemented | PRE-M-PHASE-AUDIT §2 | medium | standalone |
| 2 | `SESSION-RESUME-2026-07-18.md` references wrong branch (`refactor/structure-audit-2026-07-17`) and lists PHASE13-17 as "pending" (all done) | SESSION-RESUME L3, L167-175 | trivial | standalone |
| 3 | `ROADMAP.md` shows HEAD=`b4b4ed2`, branch wrong, PHASE13-17 listed "pending" (all complete) | ROADMAP L5-8, L87 | trivial | standalone |
| 4 | No shellcheck pass on `scripts/*.sh tools/*.sh` before merge — risk of latent bugs | PRE-M-PHASE-AUDIT §3 | medium | standalone |

## Recommended (fix soon, not blocking)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 5 | Queue sync race — no-sync is intentional but prevents retry across nodes | PRE-M-PHASE-AUDIT §2, BURNIN-SMOKE-REPORT | medium | standalone |
| 6 | Guest verifier process exited after 2 tasks — root cause unknown | PRE-M-PHASE-AUDIT §2, BURNIN-SMOKE-REPORT | medium | needs investigation (#15) |
| 7 | Duplicate lib functions: `uom-lib.sh` vs `tools/uom-state-lib.sh` overlap | PRE-M-PHASE-AUDIT §3 | medium | standalone |
| 8 | Tool overlap: `tools/uom-sync-loop.sh` (old) vs `tools/uom-smoke-sync.sh` (new) | PRE-M-PHASE-AUDIT §6 | small | standalone |
| 9 | Duplicate gateway detection: `uom-net-detect.sh` and `uom-ip-discover.sh` both implement independently | TODO inventory, NETWORK-AUTOSWITCH-AUDIT.md:79 | small | standalone |
| 10 | `docs/PHONE-SETUP.md` lists stale known issues (tunnel port 18022, queue corruption) | TODO inventory, PHONE-SETUP.md:153-158 | small | standalone |
| 11 | `docs/SYNC-ARCHITECTURE.md` — queue.json stale runtime changes, no .git on guest | TODO inventory, SYNC-ARCHITECTURE.md:56-60 | small | standalone |
| 12 | ~30% of commits are docs-only — consider squashing before merge | PRE-M-PHASE-AUDIT §6 | trivial | standalone |
| 13 | `docs/README-CONFLICT-ANALYSIS.md` has stale references to Phase 10-13 being "pending" | TODO inventory L17 | small | standalone |
| 14 | 41 commits / 125 files / +10145 lines on burn-in branch — large diff vs main | PRE-M-PHASE-AUDIT §6 | medium | merge plan (exists) |

## Deferred (acknowledged, intentionally postponed)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 15 | PHASE17.9 8-hour burn-in — deferred after smoke test PARTIAL PASS | BURNIN-SMOKE-REPORT, this session | large | standalone |
| 16 | Free tier LLM output quality (bad shebangs, dryrun FAILs) — accepted as normal | PRE-M-PHASE-AUDIT §2 | — | accepted |
| 17 | Merge `burnin/dual-agent-20260718` → `main` — explicitly deferred to dedicated session | PHASE17-MERGE-PLAN.md, this session | large | items 1,4,14 |
| 18 | Deploy updated scripts to phone/guest — blocked until merge | SESSION-RESUME-2026-07-18 L174 | medium | item 17 |

## Unknown (needs investigation)

| # | Item | Source | Effort | Depends On |
|---|------|--------|--------|------------|
| 19 | Guest verifier instability — why did PID 5354 exit after 2 tasks? OOM? Phantom process killer? QEMU TCG slowdown? | PRE-M-PHASE-AUDIT §2, BURNIN-SMOKE-REPORT | medium | access to guest logs at time of crash |
| 20 | Phone-side dryrun verification — `scripts/uom-dryrun.sh` on phone was never tested in this session | SESSION-RESUME-2026-07-18 L175 | small | phone SSH access |
| 21 | ShellCheck results — not run, unknown how many warnings/errors exist | PRE-M-PHASE-AUDIT §3 | small | run `shellcheck` |
| 22 | Sync race window — how often does the no-sync design cause retries to be lost? | BURNIN-SMOKE-REPORT | medium | add instrumentation to sync loop |
| 23 | QEMU guest `/` at 77% disk — could cause verifier crashes | observed during session (df output) | small | check guest disk and free space |
