# 🛰️ Universal Omni-Master (UOM)

**The Universal Bare-Metal Provisioning & Self-Healing Engine**

![POSIX sh](https://img.shields.io/badge/shell-POSIX%20sh-success?logo=gnubash&logoColor=white)
![BusyBox](https://img.shields.io/badge/BusyBox-ash--safe-blue?logo=busybox)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://img.shields.io/badge/tests-260%2B-brightgreen)
![Release](https://img.shields.io/badge/release-v0.26.0-blueviolet)

> One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc. Any terminal. Any failure mode.

---

## What is Universal Omni-Master?

UOM is a strictly POSIX-compliant Linux deployment, orchestration, self-healing, and fleet-management framework. Born from a degraded dual-boot HP Pavilion (muxless AMD dGPU, failing SATA cable, 4GB RAM, legacy BIOS), every fix was generalized into portable abstractions.

The entire framework — **16 CLI tools and 40+ library modules** — compiles into a single self-extracting POSIX shell script. No Python, no Git, no dependencies on the target.

### Capabilities
- **Universal Bootstrap**: Boot any Live ISO, run `curl | sh`, UOM deploys
- **Crash-Resume**: Power fails mid-install → re-run seed script → resumes exactly
- **Adaptive TUI**: Desktop 16:9 wide grids; Android Termux 9:16 vertical menus
- **Fleet Orchestration**: Parallel SSH, swarm policies, aggregated telemetry
- **Security**: TPM2-LUKS binding, UKI validation, SBAT auditing, STIG/CIS compliance
- **Declarative Manifests**: INI-based desired-state with idempotent apply
- **SaaS**: Free trial, pay-per-use, weekly/monthly subscriptions with usage accounting
- **AI-Patcher**: LLM-assisted error rectification with ephemeral API keys
- **OpenClaw Bridge**: Anonymized commercial telemetry for automated sales targeting

---

## Milestone Status (M1–M26)

| Phase | Milestones | Status | Tags |
|---|---|---|---|
| Foundation | M1–M6 | ✅ Sealed | v0.1.0–v0.6.0 |
| Deployment & Healing | M7–M12 | ✅ Sealed | v0.7.2–v0.12.0 |
| Ecosystem & Fleet | M13–M15 | ✅ Sealed | v0.13.0–v0.15.0 |
| Intelligence | M16–M20 | ✅ Sealed | v0.16.0–v0.20.0 |
| Commercial | M21–M26 | ✅ Sealed | v0.21.0–v0.26.0 |

**Current release: v0.26.0** — 16 CLI tools, 260+ test assertions, all gates green.

---

## The 16-Tool CLI Surface

| Command | Domain | Purpose |
|---|---|---|
| `omni-detect` | Discovery | Hardware/software topology |
| `omni-service` | Init | Service control across 5 init backends |
| `omni-boot` | Bootloader | GRUB/systemd-boot inspection and repair |
| `omni-gpu` | Graphics | Hybrid GPU policy enforcement |
| `omni-storage` | Storage | SMART/NVMe/Btrfs telemetry |
| `omni-audit` | Logging | Structured NDJSON event log |
| `omni-deploy` | Installer | Full-disk partition → bootstrap → boot |
| `omni-healer` | Watchdog | Self-healing daemon |
| `omni-snapshot` | Btrfs | Snapshot lifecycle + staged rollback |
| `omni-security` | SecOps | TPM2/UKI/SBAT hardening |
| `omni-fleet` | Swarm | Parallel SSH + swarm policies |
| `omni-manifest` | Config | Declarative desired-state engine |
| `omni-saas` | SaaS | License validation + tier switching |
| `omni-patcher` | AI | LLM-assisted auto-remediation |
| `omni-compliance` | Compliance | STIG/CIS enforcement + NDJSON audit |
| `omni-openclaw` | Commercial | Telemetry bridge for AI sales agent |

---

## Quick Start

```sh
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

./bin/omni-detect
./scripts/build-monolith.sh /tmp/omni.sh
./bin/omni-deploy plan --distro alpine --disk sda
