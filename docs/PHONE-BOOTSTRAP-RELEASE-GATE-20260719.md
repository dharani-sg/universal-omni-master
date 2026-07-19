# Phone Bootstrap Release Gate — 2026-07-19

**Branch:** `fix/phone-bootstrap-release-gate-20260719`
**Candidate SHA:** `9c00f11`
**Candidate URL:** `https://raw.githubusercontent.com/dharani-sg/universal-omni-master/9c00f11/install/bootstrap.sh`
**Date:** 2026-07-19

## Old Live Behavior (Before Fix)

The original `bootstrap.sh` and `bootstrap-termux.sh` on `main` had22 defects:

### BLOCKER (3)
1. `--check` mode created files (opencode config, src/ directory) — not read-only
2. Argument forwarding broken (`curl|bash` pattern doesn't forward `"$@"`)
3. No download validation before execution (executed arbitrary content)

### HIGH (7)
4. Hardcoded IP `192.168.40.90`
5. Hardcoded hostname `hp-pavilion`
6. Hardcoded user `alpine`
7. SSH config overwrite (no managed block)
8. `StrictHostKeyChecking=no` (insecure)
9. No checksum validation
10. `curl|bash` pattern (security risk)

### MEDIUM/LOW (10)
11-22. Non-POSIX `&>`, mutable branch ref, no Termux:Boot verification, no rollback, no idempotency, no `--verify`/`--test-root`/`--ref`, repo dir created in check mode, etc.

## Defects Fixed (22)

| Category | Count | Status |
|----------|-------|--------|
| BLOCKER | 3 | Fixed |
| HIGH | 7 | Fixed |
| MEDIUM/LOW | 12 | Fixed |
| **Total** | **22** | **All Fixed** |

### Key Fixes
- **Download-validate-execute pattern** in `bootstrap.sh`: downloads to temp file, validates shebang/size/HTML/syntax, then executes with `"$@"` forwarded
- **`--check` truly read-only** in `bootstrap-termux.sh`: no file creation, no directory creation
- **No hardcoded values**: IPs, hostnames, users all removed; use environment variables instead
- **SSH managed block**: append-only, with backup, dedup check
- **Dedicated SSH key** `id_ed25519_uom` (not default `id_ed25519`)
- **`accept-new`** instead of `StrictHostKeyChecking=no`
- **`--verify` mode** for post-install validation
- **`--test-root` mode** for isolated testing
- **`--ref` / `--rollback` / `--resume`** flags
- **Lock mechanism** with stale detection
- **Interrupt traps** for cleanup
- **POSIX sh** throughout (no `&>`, no bashisms)
- **JSON-escaped metadata** with `json_escape` helper
- **`UOM_SDK_OVERRIDE`** env var for testing on non-Android

## Test Results

### Automated Tests
- **72/72 assertions PASS** (0 failed, 0 skipped)
- Test harness: `tests/test-phone-bootstrap.sh`
- Results: `tests/results/phone-bootstrap-results.json`

### Phone Lab (Same-Phone Isolated)
- **RUN_ID:** 20260719T045706Z
- **Device:** MI 8 aarch64, Android 15 (SDK 35)
- **Lab peak:** 232 KiB (well under 2560 MiB hard limit)
- **Steps B1-B9:** ALL PASS

| Step | Result |
|------|--------|
| B1: Lab creation | PASS |
| B2: Integrity baseline | PASS |
| B3: Script transfer | PASS |
| B4: Read-only preflight | PASS (0 new files) |
| B5: Shadow apply | PASS |
| B6: Idempotency | PASS |
| B7a: Stale lock drill | PASS |
| B7b: SIGTERM drill | PASS |
| B7c: Rollback drill | PASS |
| B8: Integrity re-record | PASS (UNCHANGED) |
| B9: Evidence pullback | PASS |

### Immutable URL (From Phone)
- **Steps C1-C4:** ALL PASS

| Step | Result |
|------|--------|
| C1: URL accessible | PASS (HTTP 200) |
| C2: Download + validate | PASS (SHA-256 matches) |
| C3: Full delivery chain | PASS (check + apply from URL) |
| C4: Negative tests | PASS (404 → nonzero) |

### Phone Integrity
- **Before:** SHA-256 `2dc9628...` (SSH config), 6 keys, 1 boot file, repo at `cfd8454`
- **After:** SHA-256 `2dc9628...` (SSH config), 6 keys, 1 boot file, repo at `cfd8454`
- **Result:** UNCHANGED (only lab dir created)

## Remaining Manual Gate

See `docs/PHONE-FRESH-INSTALL-MANUAL-GATE.md` for the18-step fresh-phone test matrix.

**RELEASE_READY is forbidden until this manual gate passes.**

## Rollback Instructions

If the installer needs to be rolled back after apply:

```sh
sh install/bootstrap-termux.sh --apply --rollback --test-root <test-root>
```

This removes:
- UOM-managed SSH config block
- Termux:Boot script

Does NOT remove:
- Generated SSH keys (manual cleanup required)
- Repository clone (manual cleanup required)

## Important Notes

- **LIVE main URL REMAINS BROKEN** until the installer branch is merged to main (human decision, not this session)
- **DO NOT merge** `fix/phone-bootstrap-release-gate-20260719` to `main` until the manual fresh-phone gate passes
- **DO NOT tag** any release until all gates pass
- **Max classification this session:** RELEASE_CANDIDATE_READY_FOR_FRESH_PHONE_TEST
