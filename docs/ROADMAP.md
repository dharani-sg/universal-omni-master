# UOM Roadmap (v0.33.0-rc1 — 2026-07-18)

## Current Status

- **HEAD:** `b4b4ed2` (v0.33.0-rc1 — Phase 12 complete, R1-R6 overhaul)
- **Tag:** `uom-stable-phase12-20260718`
- **Active agent:** laptop
- **Branch:** `refactor/structure-audit-2026-07-17`
- **Current task:** PHASE13-ssh-remote-llm (pending, next to execute)
- **Pipeline queue:** PHASE13-PHASE17 (all pending)
- **Phone:** Xiaomi Mi 8, Termux, aarch64 Android
- **Laptop:** Alpine Linux 3.21, aarch64
- **Dynamic IP discovery:** Working (5-method cascade)
- **Reverse tunnel (31415→phone:8022):** UP and stable
- **Model rotation:** 4-model free pool (deepseek-v4-flash-free, nemotron-3-ultra-free, north-mini-code-free, big-pickle)

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

### ✅ Phase 5: Full Dual-Agent Loop (M30-Termux-Native)
- `bin/omni-project-start.sh` — interactive TUI dashboard with 9 sub-commands
- `bin/uom-tmux-watchdog.sh` — tmux session watchdog daemon (auto-recover)
- `install/setup-aliases.sh` — 14 UOM shell aliases for Alpine + Termux
- `bin/uom-deploy-phone.sh` — SCP-based phone deployment
- **Tunnel fix:** Removed `ExitOnForwardFailure=yes` + laptop `fuser -k` (false positives killed tunnel)
- **Result:** Tunnel 31415→phone:8022 is stable, tmux sessions auto-recover, phone boots fully automated

### 📋 Phase 6: Network Switching Stress Test ← NEXT
- Hotspot ↔ LAN ↔ mDNS transitions
- Verify tunnel survives IP changes

### 📋 Phase 7: Power-Failure Recovery Test
- Kill laptop, watch phone takeover, restore dual mode

### 📋 Phase 8: Commercialization (M44-M51)
- Enterprise bundle, Omni-Cloud managed, AI Marketplace
- Compliance Suite, FinOps Dashboard, MCP Gateway
- Edge Federation, white-label OEM

---

## Milestone Tags

| Milestone | Tag | Status |
|-----------|-----|--------|
| M1-M6 | v0.1.0-v0.6.0 | Sealed |
| M7-M12 | v0.7.2-v0.12.0 | Sealed |
| M13-M15 | v0.13.0-v0.15.0 | Sealed |
| M16-M20 | v0.16.0-v0.20.0 | Sealed |
| M21-M26 | v0.21.0-v0.26.0 | Sealed |
| M27 | v0.27.0-v0.27.4 | Sealed |
| M28 (Dual-Agent Phase 1) | v0.28.0 | Sealed |
| M29 (Bootstrap+Solo+Security) | v0.29.0 | Sealed |
| M30 (Termux-Native Tools) | v0.30.0 | Sealed |
| M31 (Dynamic Model+Port) | v0.32.0 | Sealed |
| Phase 9 (Network Auto-Switch) | uom-phone-qemu-phase9-20260718 | Sealed |
| Phase 10 (Model Rotation) | — | Sealed |
| Phase 11 (Integration Verify) | — | Sealed |
| Phase 12 (Documentation) | uom-stable-phase12-20260718 | Sealed |
| PHASE13-PHASE17 (Pipeline) | — | Pending |
| M33-M43 (Future Horizon) | — | Unscheduled |
| M44-M51 (Commercialization) | — | Unscheduled |

<!-- last-sync: 2026-07-18T23:45:00+05:30 -->