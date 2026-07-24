# Phone Fresh-Install Manual Gate

**Classification:** RELEASE_CANDIDATE_READY_FOR_FRESH_PHONE_TEST
**Date:** 2026-07-19
**Status:** PENDING — RELEASE_READY is forbidden until this gate passes

## Prerequisites

- Fresh Android 13+ ARM64 phone (or fresh Android user profile)
- Fresh Termux from official F-Droid/GitHub source (not Play Store)
- Termux:Boot plugin installed from matching source
- Internet connection (WiFi or mobile data)
- At least 500 MiB free storage

## One-Line Immutable Command

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | sh -s -- --apply --verify --profile phone-relay
```

> **Note:** Until the installer branch is merged to `main`, users must set `UOM_REF` to the candidate branch:
> ```sh
> UOM_REF=fix/phone-bootstrap-release-gate-20260719 curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | sh -s -- --apply --verify --profile phone-relay
> ```

## Manual Test Matrix

### Phase 1: Fresh Install
| # | Step | Expected | Actual | Pass/Fail |
|---|------|----------|--------|-----------|
| 1 | Install Termux from official source | App launches | | |
| 2 | Grant storage permission | `termux-setup-storage` succeeds | | |
| 3 | Run one-line command above | Exit 0, summary printed | | |
| 4 | Verify SSH key generated | `ls ~/.ssh/id_ed25519_uom` exists, mode 600 | | |
| 5 | Verify SSH config managed block | `grep UOM-MANAGED-BEGIN ~/.ssh/config` matches | | |
| 6 | Verify Termux:Boot script | `ls ~/.termux/boot/start-uom.sh` exists | | |
| 7 | Verify metadata recorded | `cat ~/src/universal-omni-master/.uom-agent/opencode-install.json` shows schema 1 | | |

### Phase 2: Pairing
| # | Step | Expected | Actual | Pass/Fail |
|---|------|----------|--------|-----------|
| 8 | Copy public key to laptop | `cat ~/.ssh/id_ed25519_uom.pub` → paste on laptop | | |
| 9 | Test SSH from laptop | `ssh -p 8022 uom@<phone-ip> echo ok` → prints "ok" | | |
| 10 | Test tmux | `ssh -p 8022 uom@<phone-ip> tmux new -s uom` | | |

### Phase 3: Reboot Survival
| # | Step | Expected | Actual | Pass/Fail |
|---|------|----------|--------|-----------|
| 11 | Reboot phone | Phone restarts normally | | |
| 12 | Termux:Boot auto-starts | SSH available within 60s of boot | | |
| 13 | SSH still works | `ssh -p 8022 uom@<phone-ip> echo ok` → "ok" | | |

### Phase 4: Idempotent Re-Run
| # | Step | Expected | Actual | Pass/Fail |
|---|------|----------|--------|-----------|
| 14 | Re-run bootstrap | Exit 0, no duplicate keys, no duplicate managed block | | |
| 15 | SSH still works after re-run | Connection succeeds | | |

### Phase 5: Rollback
| # | Step | Expected | Actual | Pass/Fail |
|---|------|----------|--------|-----------|
| 16 | Run `--apply --rollback` | Managed block removed, Termux:Boot removed | | |
| 17 | SSH config clean | No UOM-MANAGED markers remain | | |
| 18 | Re-run bootstrap after rollback | Fresh install succeeds | | |

## Exit Criteria

ALL18 steps must PASS before classification can advance to RELEASE_READY.

## Known Limitations

- Git clone inside `--test-root` fails without GitHub auth (expected, not a bug)
- `--apply` without `--skip-packages` will install companion packages on the real phone
- SIGTERM during fast operations may arrive after completion (trap fires on normal exit)

## Explicit Statement

**RELEASE_READY is forbidden until this manual gate passes with all 18 steps marked PASS.**
**Max classification this session: RELEASE_CANDIDATE_READY_FOR_FRESH_PHONE_TEST**
