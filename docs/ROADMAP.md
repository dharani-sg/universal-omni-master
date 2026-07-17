# UOM Roadmap (v0.29.0 — 2026-07-17)

## Current Status

- **HEAD:** 5f658dc / 75a051d (v0.28.0+ — dual-agent phase)
- **Kernel:** 7.2.0-rc3_1
- **Boot:** GRUB NORD theme, EFI stubs, initramfs all intact
- **Dynamic IP discovery:** Working (6-method cascade)
- **Dual-agent state machine:** Wired (schema v1), currently idle
- **Reverse tunnel (18022):** DOWN — needs phone-side start
- **Disk:** sda4=85%, sda3 (Void) unmounted
- **SATA CRC:** 5361 (degraded cable — avoid large writes to sda4)

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

### 🔄 Phase 3: Bootstrap Installer + Phone-Solo Mode (CURRENT)
- `install/bootstrap.sh` — universal curl installer
- `install/bootstrap-termux.sh` — full Termux/ARM64 setup
- `install/bootstrap-laptop.sh` — Alpine Linux setup
- `orchestrators/uom-solo-orchestrator.sh` — phone-only fallback
- `orchestrators/uom-watchdog.sh` — laptop reachability monitor

### 🚧 Phase 4: Security Hardening (CURRENT)
- `security/uom-harden-ssh.sh` — ed25519-only, key modes
- `security/uom-firewall.sh` — nftables (22, 18022, established)
- `security/install-hooks.sh` — pre-commit secret scanner
- `security/SECRETS.md` — secrets storage pattern
- `.gitignore` — secrets patterns

### 📋 Phase 5: opencode on Phone via Go Build
Termux ARM64: npm rejected, `go install` confirmed working.

### 📋 Phase 6: Full Dual-Agent Loop Active
Laptop primary, phone as verification agent.

### 📋 Phase 7: Network Switching Stress Test
Hotspot ↔ LAN ↔ mDNS transitions.

### 📋 Phase 8: Power-Failure Recovery Test
Kill laptop, watch phone takeover, restore dual mode.

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
| M28 (Dual-Agent) | v0.28.0 | ✅ Phase 1-2 done |
| **M29 (Bootstrap+Solo+Security)** | **v0.29.0** | **🚧 In progress** |

<!-- last-sync: 2026-07-17T07:35:34Z -->
