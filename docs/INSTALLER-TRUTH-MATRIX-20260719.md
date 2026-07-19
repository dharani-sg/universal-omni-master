# Installer Truth Matrix — 2026-07-19

## Files Analyzed

| Property | Burn-in (D1+D2) | Release-gate (D1 only) |
|----------|-----------------|----------------------|
| Path | `install/bootstrap-termux.sh` | `install/bootstrap-termux.sh` |
| SHA256 | `e2381e5bef40a360c6ea21990af63092822cad2bc8833eac03bb516a6ba59dc0` | `7101827804c8ecae899eae69d8e28e061e57ab1f9beb47c96cafb33f5ba1c070` |
| Owner branch | burnin/dual-agent-20260718 | fix/phone-bootstrap-release-gate-20260719 |
| Syntax check | CLEAN | CLEAN |

## Bug Matrix

| # | Criterion | Burn-in | Release-gate | Patch needed? |
|---|-----------|---------|-------------|--------------|
| C3a | `git clone --branch <SHA>` anti-pattern | YES (line 538) | NO (has fetch+checkout) | YES — burn-in |
| C3b | Tarball fallback | NO (just warn) | YES (codeload) | YES — burn-in |
| C3c | Dirty repo safety | NO | NO | YES — both |
| C5 | Key name `id_ed25519_uom` | YES | YES | No |
| C5 | UOM-MANAGED-BEGIN/END markers | NO | NO | No (nice-to-have) |
| C1a | `qemu-system-x86_64` in default pkgs | YES (line 361) | YES (line 444) | YES — both |
| C1b | Arch-aware VM backend selection | NO | NO | YES — both |
| C1c | proot-distro as default backend | NO | NO (only in docs) | YES — both |
| C1d | QEMU aarch64 experimental/opt-in | NO | NO | YES — both |
| D1 | Network gate (github unreachable) | NO | NO | YES — both |
| D1 | `REPO_STATE=skipped-network` | NO | NO | YES — both |
| D2 | `pkg update` with retry/timeout | YES (line 379, 1 attempt) | YES (3 retries, timeout 60) | Borrow release-gate logic |
| D2 | `--check` is default | YES | YES | No |
| D2 | Profiles: phone-relay/phone-vm-agent | YES | YES | No |
| D2 | `validate_consent` | YES | YES | No |
| D2 | `check_storage_guardrail` | YES | YES (partial) | No |
| D2 | Non-interactive mode | YES (`--non-interactive`) | NO | No (burn-in better) |

## Summary — Canonical file to patch
- **Primary**: `~/src/universal-omni-master/install/bootstrap-termux.sh` (burn-in, already has D1+D2 merged)
- **Secondary**: `~/src/uom-phone-bootstrap-gate/install/bootstrap-termux.sh` (has better clone logic)
- **Strategy**: Apply patches to burn-in copy; cherry-pick clone/tarball logic from release-gate copy.
