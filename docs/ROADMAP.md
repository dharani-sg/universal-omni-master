# UOM Roadmap (v0.29.1 — 2026-07-17)

## Current Status

- **HEAD:** ~v0.29.1 (README overhaul + M43-M50 commercialization)
- **Active agent:** laptop (heartbeat 13:27 IST)
- **Phone heartbeat:** 13:26 IST — dual-agent alive
- **Current task:** M02-state-sync (failed — retry pending)
- **Takeover count:** 1 (phone solo mode triggered during laptop idle)
- **Kernel:** 7.2.0-rc3_1
- **Boot:** GRUB NORD theme, EFI stubs, initramfs all intact
- **Dynamic IP discovery:** Working (6-method cascade)
- **Reverse tunnel (31415):** DOWN — needs phone-side `bash bin/uom-reverse-ssh.sh`
- **Disk:** sda4=85%, sda3 (Void) mounted and synced
- **SATA CRC:** 5361 (degraded cable — avoid large writes to primary disk)

---

## Phase 1-8 Roadmap

### ✅ Phase 1: Base System
- Alpine Linux 3.24 with OpenRC
- GRUB with NORD theme + 6 themes total
- SSH key-based auth, ed25519 only
- Dual-boot: Alpine + Void Linux

### ✅ Phase 2: Dynamic IP Discovery + Dual-Agent
- `uom-ip-discover.sh` — 6-method IP cascade
- `.uom-agent/` state machine (queue, done, state JSON)
- Dual orchestrators (laptop primary, phone secondary)
- Termux:Boot auto-start

### ✅ Phase 3: Bootstrap Installer + Phone-Solo Mode
- `install/bootstrap.sh` — universal curl installer
- `install/bootstrap-termux.sh` — full Termux/ARM64 setup
- `install/bootstrap-laptop.sh` — Alpine Linux setup
- `orchestrators/uom-solo-orchestrator.sh` — phone-only fallback
- `orchestrators/uom-watchdog.sh` — laptop reachability monitor

### ✅ Phase 4: Security Hardening
- `security/uom-harden-ssh.sh` — ed25519-only, key modes
- `security/uom-firewall.sh` — nftables (22, 31415, established)
- `security/install-hooks.sh` — pre-commit secret scanner
- `security/SECRETS.md` — secrets storage pattern
- `.gitignore` — secrets patterns

### 📋 Phase 5: Full Dual-Agent Loop Active ← NEXT
- Laptop primary, phone as verification agent
- Fix M02-state-sync (phone-side opencode PATH issue)
- Verify reverse tunnel from both devices
- Enable continuous heartbeats + task processing

### 📋 Phase 6: Network Switching Stress Test
- Hotspot ↔ LAN ↔ mDNS transitions
- Verify tunnel survives IP changes

### 📋 Phase 7: Power-Failure Recovery Test
- Kill laptop, watch phone takeover, restore dual mode

### 📋 Phase 8: Commercialization (M43-M50)
- Enterprise bundle, Omni-Cloud managed, AI Marketplace
- Compliance Suite, FinOps Dashboard, MCP Gateway
- Edge Federation, white-label OEM

---

## Milestone Tags

| Milestone | Tag | Status |
|-----------|-----|--------|
| M1-M6 | v0.1.0-v0.6.0 | ✅ Sealed |
| M7-M12 | v0.7.2-v0.12.0 | ✅ Sealed |
| M13-M15 | v0.13.0-v0.15.0 | ✅ Sealed |
| M16-M20 | v0.16.0-v0.20.0 | ✅ Sealed |
| M21-M26 | v0.21.0-v0.26.0 | ✅ Sealed |
| M27 | v0.27.0-v0.27.4 | ✅ Sealed |
| M28 (Dual-Agent Phase 1) | v0.28.0 | ✅ Sealed |
| **M29 (Bootstrap+Solo+Security)** | **v0.29.0** | **✅ Sealed** |
| **M30 (Full Dual-Agent Loop)** | **v0.30.0** | **⏳ Next** |

<!-- last-sync: 2026-07-17T08:00:00Z -->