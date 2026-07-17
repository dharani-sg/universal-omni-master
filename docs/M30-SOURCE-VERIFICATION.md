# M30 Source Verification Report

**Date:** 2026-07-17
**Verifier:** opencode (big-pickle)
**Repository:** universal-omni-master @ 0943a4e (main)
**Tag:** v0.29.0

## Environment

| Item | Value |
|---|---|
| OS | Alpine Linux 3.24 |
| Kernel | 7.2.0-rc3_1 |
| Arch | x86_64 (musl) |
| Shell | /bin/sh (BusyBox ash) |
| OpenCode | v1.17.20 |
| Disk | 85% full |
| Phone | Xiaomi Mi 8, crDroid/Android 15, Termux |

## Port Verification

| Port | Status | Notes |
|---|---|---|
| 8022 | Phone sshd | Correct in bootstrap-termux.sh (was 31415, now fixed) |
| 31415 | Reverse tunnel | Used in all scripts, docs, SSH configs |
| 18022 | Removed | Only in .uom-agent/context/ history (allowlisted) |

## POSIX Compliance

| Check | Result |
|---|---|
| All M30 scripts `#!/bin/sh` | PASS (11 scripts verified) |
| No `[[ ]]` bashisms in M30 code | PASS |
| `BASH_SOURCE` removed from state-lib.sh | PASS (replaced with `$0`) |
| No `eval` in M30 scripts | PASS |
| No `set --` in M30 scripts | PASS |
| shellcheck -s sh (core scripts) | PASS (info-level only) |

## State Library (uom-state-lib.sh)

| Check | Status |
|---|---|
| POSIX `#!/bin/sh` shebang | PASS |
| No bashisms (BASH_SOURCE removed) | PASS |
| Guard: source-safe (`_UOM_STATE_LIB_LOADED`) | PASS |
| Schema v2 migration (additive) | PASS |
| compare-and-update: mode + epoch check | PASS (recheck bug fixed) |
| Lock: mkdir-based atomic acquire | PASS |
| Lock: dead-PID recovery | PASS |
| Lock: timeout (configurable) | PASS |
| Heartbeat: runtime file (not state.json) | PASS |
| Can-write: mode-based authorization | PASS |

## Dry-Run Test Suite

| Category | Tests | Pass | Fail | Warn | Skip |
|---|---|---|---|---|---|
| Syntax | 67 | 67 | 0 | 0 | 0 |
| Static Policy | 12 | 12 | 0 | 0 | 0 |
| State & Lock | 10 | 10 | 0 | 0 | 0 |
| State Machine | 11 | 11 | 0 | 0 | 0 |
| Component | 10 | 10 | 0 | 0 | 0 |
| Live | 4 | 0 | 0 | 0 | 4 |
| **Total** | **114** | **110** | **0** | **0** | **4** |

## Fixes Applied (2026-07-17)

### Fix 1: BASH_SOURCE bashism (uom-state-lib.sh:19)
- **Before:** `_self="${BASH_SOURCE[0]:-${0}}"`
- **After:** `_self="${0}"`
- **Impact:** POSIX compliance; `BASH_SOURCE` is undefined in sh

### Fix 2: compare-and-update recheck bug (uom-state-lib.sh:303-310)
- **Before:** Recheck compared `active_agent` against old expected mode (wrong after filter changes it)
- **After:** Recheck only verifies epoch was incremented correctly
- **Impact:** Fixes "Valid confirmation was rejected" dry-run failure

### Fix 3: SSHD_PORT correction (bootstrap-termux.sh:18)
- **Before:** `SSHD_PORT=31415` (tunnel port, wrong for sshd test)
- **After:** `SSHD_PORT=8022` (correct phone sshd port) + `TUNNEL_PORT=31415`
- **Impact:** SSH config and verification steps use correct ports

### Fix 4: Git push gate (uom-orch-state.sh:82)
- **Before:** `git push origin main 2>/dev/null || true` (unconditional)
- **After:** Gated behind `UOM_ALLOW_PUSH=1`
- **Impact:** Prevents accidental pushes from orchestrators

### Fix 5: Bare /tmp writes (6 files)
- **Files:** omni-orchestrator.sh, uom-orchestrator.sh, uom-hybrid.sh, create_omni_status_alias.sh, uom-fix-connectivity.sh, uom-resume.sh
- **Before:** Hardcoded `/tmp/state_tmp.json`, `/tmp/phone_launcher.sh`, etc.
- **After:** Uses `${STATE_FILE}.tmp.$$`, `mktemp`, or `${TMPDIR:-/tmp}` patterns
- **Impact:** Safe temp file handling; no cross-user /tmp races

### Fix 6: dryrun _init_dual guard (uom-dryrun.sh:381)
- **Before:** `_init_dual()` didn't unset `_UOM_STATE_LIB_LOADED`
- **After:** Added `unset _UOM_STATE_LIB_LOADED` before sourcing state-lib
- **Impact:** Fixes state-machine tests reading from wrong fixture after test_state_lock

## Warnings (Non-Blocking)

| Warning | Classification | Action |
|---|---|---|
| curl-pipe-shell in automation | Intentional (bootstrap scripts) | Documented |
| Hardcoded IPs in orchestrators | Verify UOM_*_IP vars used | Pre-existing |
| Runbook not at expected path | Created in this session | Resolved |

## Live Checks (Skipped)

| Check | Reason |
|---|---|
| Phone shell access | Phone not reachable in this session |
| Tunnel 31415 | No live tunnel |
| OpenCode provider | N/A for verification |
| Git remote | No remote configured |
