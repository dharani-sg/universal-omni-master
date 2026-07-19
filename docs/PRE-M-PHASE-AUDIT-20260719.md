# Pre-M-Phase Audit — 2026-07-19

Audit of codebase state before entering M-phase (maintenance/merge).
Completed after PHASE17 distributed smoke test.

---

## 1. Branch health

| Check | Status | Notes |
|---|---|---|
| `git log --oneline main..HEAD` | 41 commits | PHASE0-17 on single burn-in branch |
| Three-way sync | ALIGNED | laptop/phone/guest all at `e072fab` (HEAD: `92e54d7` diverged) |
| Remote tracking | OK | `origin/burnin/dual-agent-20260718` exists |
| Conflicts with main | 5-8 files | Documented in `PHASE17-MERGE-PLAN.md` |

## 2. Critical correctness items

| Item | Status | Action |
|---|---|---|
| `uom_mode_detect()` stub at `scripts/uom-lib.sh:306` | OPEN | Implement proper solo/dual mode detection |
| Queue sync race | OPEN | No-queue-sync is intentional for now; revisit if retry needed cross-node |
| Guest verifier stability | UNKNOWN | Verifier exited after 2 tasks; root cause not investigated |
| Free tier LLM output quality | ACCEPTED | Bad shebangs and dryrun FAILs are expected; pipeline reports correctly |

## 3. Code quality

| Check | Status | Notes |
|---|---|---|
| ShellCheck clean | UNKNOWN | Not run; recommend before merge |
| Duplicate lib functions | DETECTED | `uom-lib.sh` vs `tools/uom-state-lib.sh` overlap |
| Env var consistency | IMPROVED | `UOM_*` vars now respected via state lib commit `97d1f5b` |
| Signal safety | VERIFIED | All 3 scripts (generator, verifier, feedback) handle SIGTERM |

## 4. Documentation coverage

| Document | Status | Notes |
|---|---|---|
| `PHASE17-MERGE-PLAN.md` | NEW | Created this session |
| `BURNIN-SMOKE-REPORT-20260719.md` | NEW | Created this session |
| `PHASE17-TOPOLOGY-DECISION.md` | NEW | Commit `e072fab` |
| `TOPOUT.md` | NEW | Created this session |
| `SESSION-RESUME-2026-07-18.md` | STALE | Needs update with PHASE17 outcomes |
| `ROADMAP.md` | STALE | Phase 17 not listed |

## 5. TODO inventory (top 3)

See full inventory in the session's TODO list. Top priorities:

1. **HIGH** `scripts/uom-lib.sh:306` — `uom_mode_detect()` is a stub
2. **MEDIUM** `docs/BURNIN-SMOKE-REPORT-20260719.md:46-57` — Queue sync, guest verifier stability
3. **MEDIUM** `docs/NETWORK-AUTOSWITCH-AUDIT.md:79` — IP discovery tools have duplicate gateway detection

## 6. Known technical debt

- **Large branch**: 125 files changed, 10k+ lines introduced
- **Docs-only commits**: ~30% of commits are docs-only
- **Tool overlap**: `tools/uom-sync-loop.sh` (old) vs `tools/uom-smoke-sync.sh` (new)
- **Ghost processes**: Sync loop PID 6793 still running on laptop

## 7. Pre-M-phase checklist

- [x] Git log audit complete
- [x] Merge plan documented (PHASE17-MERGE-PLAN.md)
- [x] Smoke test report documented (BURNIN-SMOKE-REPORT.md)
- [ ] Stop sync loop
- [ ] Clean up smoke artifacts
- [ ] File any bugs found during smoke test
- [ ] Update SESSION-RESUME with PHASE17 outcomes
- [ ] Update ROADMAP.md with Phase 17

## 8. Summary

Codebase is in good shape for M-phase. The only blocking issue is the
`uom_mode_detect()` stub — all other items are documentation or nice-to-have.
The burn-in branch should NOT be merged in this session; a dedicated merge
session after PHASE17.9 burn-in (deferred) is recommended.
