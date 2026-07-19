# PHASE17 Merge Plan — burnin/dual-agent-20260718 → main

## Status
**Do NOT merge in this session.** The burn-in branch is for PHASE17 testing only.
This plan exists for documentation and eventual merge.

---

## Branch topology

```
main  ──●──────────────────────────────────────────────
           \                                          /
burnin/dual-agent-20260718  ●...●...●...●...●...●...● (HEAD)
                            ^--- 41 commits, 125 files ---^
```

## Merge base

`b68fcbb` — shared ancestor with main. Diff: +10145 / -7120 across 125 files.

---

## Commit classification (PHASE0-17, 41 commits)

### Tier 1 — Must-merge (PHASE13-17 core)

| SHA | Message | Risk |
|-----|---------|------|
| `48fe98a` | fix(phase17): correct burn-in supervisor, sync safety, feedback protocol | Low |
| `97d1f5b` | fix(phase17): state lib respects env overrides for all paths | Low |
| `f1eec5c` | fix(phase17): add UOM_QUEUE_FILE/UOM_STATE_DIR sandbox overrides | Low |
| `3e7c176` | fix(phase17): verifier retry logic for FAIL (pend + attempts counter) | Medium |
| `1e08de9` | fix(phase17): retry deadlock + signal-safe sleep | Medium |
| `38f1cf2` | fix(phase17.retry): regenerate on pending+done, archive, abandon | Medium |
| `92e54d7` | fix(phase17.signals): SIGTERM/INT/HUP handlers, shutdown flag | Low |
| `e072fab` | docs(phase17): topology decision | None |
| `9d8560b` | PHASE14-17: Phone gen loop, sync loop, feedback aggregator | High |
| `6238222` | PHASE13: Preflight recovery, SSH fix, queue tool, live LLM test | High |
| `5393727` | R6: Update ROADMAP.md + SESSION-RESUME | None |
| `b4b4ed2` | R5: Queue reconcile M33-M37 → PHASE13-17 | None |

### Tier 2 — Should-merge (PHASE0-12 improvements)

Commits `2117f8c` through `44443c5` (Phase 0-12) contain infrastructure fixes
(dynamic model selection, network fingerprinting, crash safety, watchdog
consolidation) that should be merged.

### Tier 3 — Docs-only / Chore

| SHA | Message |
|-----|---------|
| `5393727` | R6: Update ROADMAP.md + SESSION-RESUME |
| `b4b4ed2` | R5: Queue reconcile M33-M37 |
| `7007605` | docs: update SESSION-RESUME |
| `b0c654c` | docs+fix: v0.32.0 session merge |

---

## Recommended merge strategy

1. **Phase 13-17 (10 commits, Tier 1):** `git merge --squash` into main for
   clean integration. These are the only commits tested in this session.

2. **Phase 0-12 (30 commits, Tier 2):** Already deployed and tested in
   previous sessions. Can merge as-is (no conflicts expected with Tier 1).

3. **Excluded:** None. All 41 commits are valid improvements.

---

## Conflicts expected

| File | Conflict type | Resolution |
|------|---------------|------------|
| `tools/uom-state-lib.sh` | Both branches added env-override support | Accept burn-in (more complete) |
| `scripts/orchestrator-main.sh` | Rewrite in both | Accept burn-in |
| `docs/SESSION-RESUME.md` | Append vs rewrite | Keep both, deduplicate |
| `docs/ROADMAP.md` | Phase listing diff | Accept burn-in |

---

## Pre-merge checklist (for future session)

- [ ] `git diff main..HEAD --stat` — review all 125 files
- [ ] `git log --oneline main..HEAD` — verify exact commit set
- [ ] `git merge --no-ff --no-commit` — dry run, check conflicts
- [ ] Resolve conflicts per above table
- [ ] Run `shellcheck scripts/*.sh tools/*.sh`
- [ ] Deploy to phone + guest, run PHASE17.9 smoke test (TBD)
- [ ] Commit merge, tag `v0.33.0`

---

## This session's scope

**Do NOT merge.** Document only. Merge will happen in a dedicated session
after PHASE17.9 burn-in (deferred) and full regression test.
