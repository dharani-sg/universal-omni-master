# UOM Session Resume — 2026-07-20 (Updated 12:10 IST)

Generated from wakeup refactor session.

---

## Active State (Wakeup Refactor 2026-07-20 11:55-12:10 IST)

- **Current branch:** `main`
- **HEAD:** `5d68be8` — docs(readme): full overhaul
- **Working tree:** dirty — bootstrap-termux.sh, config/phone/opencode-phone.json, orchestrators/uom-trident-v2.sh, orchestrators/uom-git-sync.sh, tools/uom-device-bundle-push.sh, tools/uom-device-bundle-pull.sh, resume.md, .uom-agent/journal.jsonl
- **Pre-push hook:** DENY-ALL (reinstalled, sha256: cd4df280...)

---

## Triple-Agent Architecture

| Device | Role | OpenCode | Status |
|--------|------|----------|--------|
| Laptop (192.168.40.90) | Hub + orchestrator | v1.18.3 native | **ONLINE** |
| Phone1 (P20 Pro, u0_a608) | Worker + relay | v1.2.13 via relay→laptop | **PROVEN** (PHONE1_OK) |
| Phone2 (Poco, u0_a217) | Worker (proot) | relay→laptop | **PROVEN** (PHONE2_OK) |

### Phone1 (P20 Pro, 192.168.40.207:8022)
| Service | Status | PID/Runtime |
|---------|--------|-------------|
| uom-sshd | **RUN** | pid 24440 |
| uom-tunnel | **RUN** (→ laptop:31415) | pid 18596 (restarted) |
| uom-idle-agent | **RUN** (30s poll, full env) | pid 3359 |
| uom-qemu | **RUN** (Alpine VM, :2222) | pid 25274 |
| VM mesh agent | **DEPLOYED** (status exits cleanly) | via Phone1 Termux hop |

### Phone2 (Poco, 192.168.40.157:8022)
| Service | Status | PID/Runtime |
|---------|--------|-------------|
| uom-sshd | **RUN** | pid 26609 |
| uom-tunnel | **RUN** (→ laptop:31416) | pid 21972 |
| uom-idle-agent | **RUN** (30s poll, full env) | pid 28982 |
| uom-qemu | **DOWN** (degraded, proot worker) | marked down permanently |

---

## Flaw Fixes (Wakeup Refactor)

| Flaw | Description | Status |
|------|-------------|--------|
| F1+F2 | Phone1 opencode relay direction — SSH to laptop LAN, not local :31415 | **FIXED** |
| F3 | Phone2 opencode proven (PHONE2_OK) | **FIXED** |
| F4 | Phone2 QEMU degraded to proot worker; qemu service stopped | **FIXED** |
| F5 | VM mesh agent `status` exits cleanly (not daemon loop) | **FIXED** |
| F6 | Bootstrap tunnel uses live discovery (gateway, cache, port map by whoami) | **FIXED** |
| F7 | Triple git sync: bundle protocol (status, pull-device, push-to-phones) | **FIXED** |
| F9 | IDLE agent runit env: full TERMUX env, 30s poll, dirty bundle sync | **FIXED** |
| F11 | Broken socat relay removed | **FIXED** |

---

## Triple Git Sync

- **Protocol:** Hub-and-spoke git bundle (NO push to origin)
- **Script:** `orchestrators/uom-git-sync.sh`
- **Status:** Laptop SHA `5d68be8`. Phones unreachable (laptop on 10.106.203.90, phones on 192.168.40.x)
- **sync-status.json:** `.uom-agent/sync-status.json`

### Sync Commands
```bash
bash orchestrators/uom-git-sync.sh status          # all 3 device SHAs
bash orchestrators/uom-git-sync.sh sync-status     # write sync-status.json
bash orchestrators/uom-git-sync.sh pull-device phone1  # pull phone1 bundle to laptop
bash orchestrators/uom-git-sync.sh push-to-phones  # push laptop hub bundle to phones
```

---

## Bootstrap Installer Updates

- **File:** `install/bootstrap-termux.sh`
- **Runit services:** Creates uom-sshd, uom-tunnel, uom-idle-agent during `--apply`
- **Tunnel discovery:** Gateway cache, port map by whoami (u0_a608→31415, u0_a217→31416)
- **Boot script:** Uses SVDIR, starts all runit services
- **Verification:** Checks runit service presence

---

## Network Note (2026-07-20 ~12:00 IST)

Laptop WiFi moved from 192.168.40.90 → 10.106.203.90. Phones on 192.168.40.x cannot be reached via LAN. Reverse tunnels (port 31415/31416) also down. This is transient — when laptop returns to 192.168.40.x network, tunnels will auto-reconnect.

---

## Remaining Manual Actions

1. **Termux:Boot APK** — Install from F-Droid on both phones
2. **Battery optimization** — Set Termux to "Unrestricted" in Android Settings
   - MIUI/HyperOS (Phone2): Settings > Apps > Manage apps > Termux > Battery saver > No restrictions
   - EMUI/Huawei (Phone1): Settings > Battery > App launch > Termux > toggle OFF auto-manage
3. **End-to-end verification** — Pending (phones unreachable on current WiFi)
4. **Task round-trip test** — Pending (requires phone connectivity)
