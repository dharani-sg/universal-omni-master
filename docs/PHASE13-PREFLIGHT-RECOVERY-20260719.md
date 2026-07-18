# PHASE13 Preflight Recovery — 2026-07-19

## Incident: INVALID_BULK_CLAIM

At 2026-07-19 ~00:10 UTC, preflight inspection (PHASE13.A) found the phone
(hash `ebe18b6`) had autonomously marked 5 queue tasks M33–M37 as
`in_progress` with `generator_note: "generator-picked-up"` despite **zero**
generator/verifier/reconciler processes running and no runtime directory
artifacts.

### Root Cause

Old generator at `scripts/uom-generator.sh` (identical at `ebe18b6` and
`5393727` — no code change between those commits) has these design flaws:

1. **No state lease check** — `_read_pending_task()` reads `queue.json`
   directly via `jq` without consulting `state.json`'s `writer_role` field.
   On the phone, `writer_role` was `laptop` (as set during Phase 12). The
   generator should have refused to pick tasks because it didn't hold the
   writer lease.

2. **No timeout on LLM calls** — `_call_llm_cloud()` blocks indefinitely on
   the `opencode` subprocess (line 199). On the phone, opencode isn't
   available and the remote script `uom-llm-remote.sh` tries SSH to the
   laptop. If the SSH connection hangs or the laptop is unreachable, the
   generator hangs forever holding the task's `in_progress` status.

3. **No restart guard for hung instances** — The singleton guard (line 84–96)
   checks PID only at startup. It does not detect if the old instance is
   *hung* (responsive but stuck in LLM call). If the orchestrator restarts
   the generator after a timeout, the new instance finds the previous one's
   PID still alive and exits (correct), but a different restart mechanism
   (e.g., crond, TMUX auto-respawn) that bypasses the PID check can spawn
   duplicate instances. Each duplicate picks the *next* pending task since
   prior tasks are now `in_progress`.

4. **Race across generator restarts** — The loop at line 304 selects the
   *first* pending task by priority. If instance #1 hangs on M33
   (now `in_progress`), instance #2 selects M34, marks it `in_progress`,
   hangs. Repeat for M35–M37. This explains how all 5 tasks were
   `in_progress` with no output.

### Impact

- Queue integrity was compromised: 5 phantom `in_progress` entries with no
  corresponding artifacts.
- `state.json` was NOT modified by the generator (it only touches
  `queue.json`), so state remained internally consistent.
- No scripts were generated — all tasks were stuck in the hung/restart cycle
  before LLM output could complete.

### Resolution

1. **Queue cleaned** — All M33–M37 reset to `pending` (R5).
2. **Tasks renamed** — M33–M37 → PHASE13–PHASE17 under OPTION 2 (phase-based
   naming) with horizon labels M33–M43 in README to prevent naming collision.
3. **Context files renamed** — 5 context files updated to PHASE13–PHASE17.
4. **Phone git state fixed** — Phone ff-forwarded from `ebe18b6` to
   `5393727` (tag `uom-stable-phase12-20260718`), matching laptop and guest.
5. **Forensic snapshot captured** — All pre-cleanup files preserved at
   `~/uom-vm/backups/phase13-preflight-20260719-002353/`.

### Code Fixes Applied (PHASE13.A10)

`bin/uom-ssh-phone.sh` gateway pattern (line 79) expanded from
`192.168.43.1|10.42.*.1` to `192.168.43.*|192.168.40.*|10.42.*` to match
Xiaomi Mi 8 hotspot subnet `192.168.40.x`.

### Script SHA Verification (PHASE13.A11)

Triple match (laptop / phone / guest) confirmed for all 8 core scripts
at commit `53937273bf8f3dab04f4aa46242c7cad4801de53`.

### Residual Risks

1. Generator still has no timeout on LLM calls — will hang forever if
   `opencode` or remote LLM script hangs. Fix deferred to Phase C
   (blocking consistency fixes).
2. Generator bypasses `state.json` lease — still reads/writes `queue.json`
   directly. Fix deferred to Phase C.
3. No `tools/uom-queue.sh` exists (missing from repo) — queue operations
   are ad-hoc. Fix deferred to Phase C.
4. 17 untracked stale orphan files on phone, 22 on guest — pre-cleanup
   artifacts, no functional impact.
