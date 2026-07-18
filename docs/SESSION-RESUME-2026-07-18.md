# SESSION RESUME — 2026-07-18 (Evening Session)

Repo: `universal-omni-master` | branch: `refactor/structure-audit-2026-07-17` | HEAD: 75f81b8`6000b8f`
Previous session: 2026-07-18 morning (see below for earlier session details)

## Current State (as of 2026-07-18 19:50 IST)

| Item | Value |
|------|-------|
| **Branch** | `refactor/structure-audit-2026-07-17` |
| **HEAD** | `6000b8f` — fix(widgets): skip disk-validate on locked qcow2; monitor-based shutdown fallback |
| **Phone IP** | `10.21.250.112:8022` (Redmi 13C hotspot subnet) |
| **Laptop IP** | `10.21.250.90` |
| **SSID** | Redmi 13C |
| **Phone SSH** | UP — key-based, port 8022, user `u0_a608` |
| **QEMU** | RUNNING on phone — pid-file tracked, tmux `uom-qemu-host` |
| **Guest** | Alpine 3.21 aarch64, kernel 6.12.95-0-virt, SSH on port 2222 |
| **Guest user** | `uom` (uid=1000) |
| **Reverse tunnel** | DOWN (not started this session) |
| **T1-T10 dry-run** | 10/10 PASS — evidence in `docs/DRYRUN-T1-T10-20260718.md` |

## Last Checkpoint

```
6000b8f fix(widgets): skip disk-validate on locked qcow2; monitor-based shutdown fallback
  Changes: bin/uom-qemu-phone, scripts/phone-shortcuts/90-UOM-Stop,
           scripts/phone-shortcuts/tasks/10-UOM-Start, docs/DRYRUN-T1-T10-20260718.md
```

## What was done this evening session (19:10–19:46 IST)

1. **Phone SSH recovery** — Phone was on new network (10.21.250.x), SSH auth failed.
   Generated manual repair script. User ran it on phone Termux. SSH restored.
2. **QEMU cold start** — Started QEMU, waited for Alpine guest boot (~3min).
3. **T1-T10 dry-run** — All 10 tests PASS.
4. **T2 bug fix** — `10-UOM-Start` falsely reported corrupted disk when QEMU holds qcow2 lock.
   Fix: skip `qemu-img info` validation when `uom_qemu_running` returns true.
5. **T8 bug fix** — Guest lacks doas/sudo for poweroff. Added QEMU monitor `system_powerdown`
   (ACPI) fallback in both widget and launcher. Added `quit` fallback at 10s. Reduced timeout 60s→30s.
6. **Checkpoint commit** — `6000b8f`

## Queued work (Phase 0-8)

Phase 0 (crash + drift safety) is in progress:
- 0.1 ✅ T1-T10 results written
- 0.2 ✅ Checkpoint commit
- 0.3 🔄 Session resume + checkpoint script (IN PROGRESS)
- 0.4 🔲 Network-drift-safe SSH layer
- 0.5 🔲 Reverse-tunnel auto-recovery
- 0.6 🔲 Phase 0 final checkpoint
- Phases 1-8: 🔲 Not started

## Network notes

- Phone and laptop on different network from previous sessions (Redmi 13C, 10.21.250.x)
- Previous session used 192.168.40.x subnet
- No VPN/mesh/tailscale/zerotier installed on either device
- Phone host key unchanged (ED25519 SHA256:dBPM+vGSkHXdv91rN0ZLubvP/Oqul+N/malqz5Ph/JY)
- `~/.config/uom/last-phone-ip.txt` contains `10.21.250.112`

## Key files on phone

| File | Status |
|------|--------|
| `~/bin/uom-qemu-phone` | UPDATED (monitor fallback, 30s timeout) |
| `~/bin/90-UOM-Stop` | UPDATED (ACPI monitor fallback) |
| `~/bin/10-UOM-Start` | UPDATED (skip disk validation when running) |
| `~/bin/uom-lib.sh` | Synced with repo |
| `~/bin/uom-widget-lib.sh` | Synced with repo |

## Key phone-only scripts (NOT in repo, need reconciliation)

| File | SHA prefix | Notes |
|------|-----------|-------|
| `~/bin/uom-session.sh` | `392d62da` | Phone-only, not in repo |
| `~/bin/uom-install-alpine.sh` | `d850b9bc` | Phone-only, not in repo |
| `~/bin/uom-status.sh` | `4dfe8992` | Phone ahead of repo (`6dad10c1`) |
| `~/bin/uom-reverse-ssh.sh` | `fd341a39` | Phone ahead of repo (`be347aba`) |
| `~/bin/uom-tmux-watchdog.sh` | `17862c3e` | Phone ahead of repo (`b726266c`) |

## Commands to resume

```bash
# From laptop — SSH to phone:
ssh -i ~/.ssh/id_ed25519_phone -p 8022 u0_a608@10.21.250.112

# Check QEMU status:
ssh -i ~/.ssh/id_ed25519_phone -p 8022 u0_a608@10.21.250.112 '~/bin/uom-qemu-phone status'

# Check guest SSH:
ssh -i ~/.ssh/id_ed25519_phone -p 8022 u0_a608@10.21.250.112 \
  'ssh -o BatchMode=yes -p 2222 uom@127.0.0.1 "echo OK; hostname; uptime"'

# Checkpoint commit (from repo):
sh bin/uom-checkpoint.sh "message here"

# Continue queued work:
# Phase 0.4 — Network drift safe SSH
# Phase 0.5 — Reverse tunnel recovery
```

---

## Earlier session details (2026-07-18 morning)

### Part 1-3: Deep Phone Audit (08:46–09:30 IST)

**Device:** Xiaomi MI 8 (dipper), crDroid Android 15, kernel 4.9.337-perf
**Termux:** 114 packages upgraded, apt CLEAN, no foreign contamination
**Debian proot:** CLEAN, 239 packages, node/npm/opencode working
**QEMU:** WORKING (direct kernel boot with earlycon=pl011)
**opencode:** Termux v1.2.13 (preferred), proot v1.18.3 (fallback)
**SSH:** port 8022, openssh 10.4p1 (upgraded during session, required manual sshd restart)

Key findings:
- Previous "mixed PGP signatures" concern was UNFOUNDED — system was already clean
- Previous "QEMU requires PTY" was WRONG — earlycon parameter was the real fix
- Queue.json corruption from 2026-07-17 caused phone orchestrator failures
- ENOSYS statx() is a kernel limitation (4.9), not package pollution

<!-- last-sync: 2026-07-18T19:50:00+05:30 -->
