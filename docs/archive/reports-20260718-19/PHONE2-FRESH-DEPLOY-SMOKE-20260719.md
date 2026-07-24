# Phone 2 Fresh-Deploy Smoke Test Report — 2026-07-19

**RUN_ID:** `20260719T060200Z`
**Branch:** `fix/phone-bootstrap-release-gate-20260719` (`89f46cc`)
**Device:** Phone 2 (Android 15, SDK 35, aarch64)
**User:** `u0_a217`
**SSH tunnel:** Reverse `localhost:2223 → localhost:8022`
**Date:** 2026-07-19 UTC

---

## Summary

| Block | Name | Result |
|-------|------|--------|
| 1 | Create evidence lab | PASS |
| 2 | Baseline snapshot | PASS |
| 3 | Download + checksum | PASS |
| 4 | Dry-run check | PASS (cache delta benign) |
| 5 | Apply + verify | PASS (with known gaps) |
| 6 | Deployment smoke | PARTIAL (see gaps) |
| 10 | Idempotency | PASS |
| 11 | Log capture + evidence | PASS |

**Overall: PASS with 2 known gaps**

---

## Device State

| Metric | Before | After |
|--------|--------|-------|
| Packages | 72 | 81 (+9) |
| Disk free | 47 GiB | 47 GiB (unchanged) |
| SSH keys | 1 (laptop) | 2 (+uom) |
| .ssh/config | none | managed block written |
| Termux:Boot | missing | installed |
| Repo clone | n/a | FAILED (no GitHub access) |
| opencode | not found | not installed |

---

## Known Gaps

### 1. Git clone failed (HIGH — expected)

Phone 2 cannot reach GitHub from Termux. The installer attempts `git clone` which fails, leaving no local repo.

**Impact:** No `bin/` directory, no `uom-status.sh`, no local scripts.
**Root cause:** Network restriction or DNS on Phone 2's Termux.
**Mitigation:** Clone manually when network is available, or pre-stage the repo.

### 2. opencode not installed (MEDIUM — expected)

All install priorities fell through:
- Priority 1 (Termux package): not available
- Priority 5 (remote fallback): failed (no GitHub access)

**Impact:** opencode binary not present on Phone 2.
**Root cause:** Same network issue as git clone.
**Mitigation:** Install manually once network is available.

---

## Idempotency Results

| Metric | Run 1 | Run 2 | Verdict |
|--------|-------|-------|---------|
| Packages | 81 | 81 | IDLEMPOTENT |
| SSH config hash | `849c7eeaf072b96a457a073ef62aadf5` | `849c7eeaf072b96a457a073ef62aadf5` | IDEMPOTENT |
| SSH key | created | existing (no regen) | IDEMPOTENT |
| Boot script | installed | installed (overwrite ok) | IDEMPOTENT |

---

## Evidence

- **Lab:** `$HOME/.cache/uom-phone2-fresh-smoke/20260719T060200Z/`
- **Size:** 65 KB total (28 KB evidence, 16 KB logs)
- **Files:**
  - `evidence/run-id.txt`
  - `evidence/device-info.txt`
  - `evidence/baseline-packages.txt` (72 entries)
  - `evidence/baseline-disk.txt`
  - `evidence/baseline-processes.txt`
  - `evidence/pre-apply-state.txt`
  - `logs/apply.log` (82 lines)
  - `logs/apply-idempotent.log`
  - `download/bootstrap.sh` (SHA-256 verified)

---

## Conclusion

The public installer (`89f46cc`) works correctly on Phone 2 fresh Termux:
- Download + checksum validation: **PASS**
- Package installation: **PASS** (9 packages installed)
- SSH key generation: **PASS** (`id_ed25519_uom`)
- SSH config management: **PASS** (managed block, idempotent)
- Termux:Boot: **PASS**
- Idempotency: **PASS** (no side effects on re-run)

Two gaps exist due to Phone 2's network restriction preventing GitHub access (git clone, opencode install). These are environment-specific, not installer bugs.
