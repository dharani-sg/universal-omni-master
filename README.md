<p align="center">
  <img src="https://img.shields.io/badge/shell-POSIX%20sh-success?logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/BusyBox-ash--safe-blue?logo=busybox" alt="BusyBox">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/tests-250%2B-brightgreen" alt="Tests">
  <img src="https://img.shields.io/badge/release-v0.20.0-blueviolet" alt="Release">
  <img src="https://img.shields.io/badge/cross--libc-musl%E2%86%94glibc-orange" alt="Cross-Libc">
</p>

<h1 align="center">🛰️ Universal Omni-Master (UOM)</h1>
<p align="center">
  <b>The Universal Bare-Metal Provisioning & Self-Healing Engine</b><br>
  <i>One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc. Any terminal. Any failure mode.</i>
</p>

---

## 🎯 What is Universal Omni-Master?

Universal Omni-Master (UOM) is a strictly POSIX-compliant, distribution-agnostic Linux deployment, orchestration, self-healing, and fleet-management framework. It was forged from the extreme constraints of a degraded dual-boot HP Pavilion 15-n010tx (muxless AMD dGPU, failing SATA cable with stable UDMA_CRC baseline 5360, 4GB RAM, legacy BIOS without TPM2 or Secure Boot). 

Every hardware-specific fix was generalized into portable, fixture-tested abstractions. The entire framework compiles into a **single self-extracting POSIX shell script** (`omni-monolith.sh`) that can be `scp`'d to any Linux box and run with zero dependencies.

Today, UOM is a **Class-1 Bare-Metal Provisioning Engine** capable of:
- **Universal Bootstrap**: Boot any Live ISO, run `curl | sh`, and UOM takes over.
- **Heuristic Crash-Resume**: If power or network fails mid-install, re-running the seed script resumes exactly where it left off.
- **Adaptive TUI**: Automatically detects terminal width. Desktop (16:9) renders wide grids; Android Termux SSH (9:16 portrait) reflows to thumb-optimized vertical menus.
- **Declarative State**: Define desired system state in simple INI manifests; UOM reconciles drift idempotently.
- **Live Telemetry**: Real-time, FD3-multiplexed output streaming that adapts to your screen layout.
- **Fleet Orchestration**: Manage 10+ nodes from a single TUI with parallel SSH, swarm policies, and aggregated telemetry.

---

## ✨ The UOM Manifesto (Core Principles)

| Principle | Implementation |
|---|---|
| 🐚 **POSIX-First** | `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms, zero `eval`. Fish is confined to the interactive TUI only. |
| 🧠 **Heuristic State** | Pure POSIX key=value state tracking. Power failure? Re-run the seed script — it resumes exactly where it left off. |
| 📱 **Adaptive TUI** | Detects `$COLUMNS`. Portrait (<60 cols) uses vertical numbered menus; landscape uses wide grids. Progressive disclosure for logs. |
| 🛡️ **Mutation Safety** | Any state-changing operation returns **126** when `OMNI_SYSROOT` is set, cleanly separating fixture testing from live mutation. |
| 📉 **Baseline Telemetry** | Stable UDMA_CRC = 5360 is not a failure. Alerts only on negative deltas from a stored baseline. |
| 🧩 **Monolithic Delivery** | 12 CLIs + 40+ libraries compile into one `scp`-able script. No Python, no Git, no external dependencies required. |
| 🧬 **Cross-Libc Correctness** | musl → glibc chroot with ELF interpreter bridging and efivarfs UEFI NVRAM writes. |
| 🧪 **Gate-Verified** | No milestone is tagged until its test suite AND every prior regression suite pass 100%. 250+ automated assertions. |

---

## 🗺️ Milestone Roadmap

### Phase 1–3: Foundation, Healing & Fleet (✅ SEALED)
| # | Milestone | Deliverable |
|---|---|---|
| **M1** | 🔎 Hardware/Software Detection | `omni-detect` — multi-distro fixture-based discovery |
| **M2** | ⚙️ Init/Service Abstraction | `omni-service` — systemd, OpenRC, runit, s6, dinit |
| **M3** | 🥾 Bootloader Abstraction | `omni-boot` — GRUB + systemd-boot wiring |
| **M4** | 🎮 GPU Policy Engine | `omni-gpu` — Intel/AMD/NVIDIA hybrid, muxless dGPU override |
| **M5** | 💾 Storage Telemetry | `omni-storage` — SMART/NVMe/Btrfs scrub, cable-watch |
| **M6** | 🩺 Unified Diagnostics | `omni-audit` — structured NDJSON event logging |
| **M7** | 🚀 Universal Installer | `omni-deploy` — cross-libc chroot, pacstrap, debootstrap |
| **M8** | 🤖 Self-Healing Daemon | `omni-healer` — parallel sub-daemons; dmesg poll-diff |
| **M9** | 🔌 Init Service Integration | Per-init service units for omni-healer |
| **M10** | 📸 Btrfs Snapshot Lifecycle | `omni-snapshot` — create/list/prune/periodic/hooks |
| **M11** | ⏪ Atomic Rollback | Staged RW clone + boot-to-snapshot entries |
| **M12** | 🖥️ Fish TUI Control Plane | `omni-tui` — deterministic `--no-config` isolated dashboard |
| **M13** | 📦 Monolith & Fleet Transport | POSIX bundler, SSH remote transport, plugin hooks |
| **M14** | 🛡️ Security Hardening | `omni-security` — TPM2-LUKS, UKI PE validation, SBAT |
| **M15** | 🌐 Fleet Orchestration | `omni-fleet` — POSIX batch-parallel SSH, swarm policies |

### Phase 4: The Universal Bare-Metal Blueprint (✅ SEALED at v0.20.0)
| # | Milestone | Deliverable |
|---|---|---|
| **M16** | 🧠 **Heuristic State Machine** | `src/deploy/state.sh` — pure POSIX crash-resume engine. |
| **M17** | 📱 **Adaptive TUI Engine** | `src/deploy/ui.sh` — Portrait/Landscape reflow & progressive log disclosure. |
| **M18** | 🌱 **Omni-Seed One-Liner** | `scripts/omni-seed.sh` — `curl | sh` bootstrap with durable ESP/Btrfs mirroring. |
| **M19** | 📜 **Declarative Manifests** | `omni-manifest` — INI-based desired-state drift detection & idempotent apply. |
| **M20** | 📡 **Live Telemetry Feed** | `src/deploy/livefeed.sh` — FD3 stream multiplexing without `mkfifo` or orphaned background jobs. |

### Phase 5: The AI-Augmented Fleet Era (🚧 PLANNED)
| # | Milestone | Vision |
|---|---|---|
| **M21** | 🤖 **AI-Patcher** | Auto-rectification via local USB LLM or ephemeral API keys. Auto-files GitHub issues on failure. |
| **M22** | 🖥️ **KVM Testbed** | Automated headless QEMU/KVM validation harness via serial console parsing. |
| **M23** | 📦 **Central Control Manager** | `omni-manager` — Atomic module hot-swapping for new distros/WMs with `.bak` rollback. |
| **M24** | 🌐 **SaaS & OpenClaw Sync** | Commercial licensing layer & AI sales agent integration for edge/IoT fleets. |
| **M25** | 📱 **Termux Native Polish** | Deep Android integration, haptic triggers, and native notification bridging. |

---

## 🛠️ The 12-Tool CLI Surface

UOM compiles into a single self-extracting script (`omni-monolith.sh`) containing 12 distinct POSIX CLI entrypoints:

| Command | Domain | Purpose |
|---|---|---|
| `omni-detect` | Discovery | Hardware/software topology and baseline telemetry |
| `omni-service` | Init | Agnostic service control across 5 init backends |
| `omni-boot` | Bootloader | Inspect, install, and repair GRUB/systemd-boot |
| `omni-gpu` | Graphics | Hybrid switching and muxless dGPU policy enforcement |
| `omni-storage` | Storage | SMART/NVMe/Btrfs scrub and cable-watch policy engine |
| `omni-audit` | Logging | Unified structured NDJSON event log |
| `omni-deploy` | Installer | Full-disk partition, bootstrap, chroot, bootloader wiring |
| `omni-healer` | Watchdog | Parallel self-healing daemon (storage/services/GPU) |
| `omni-snapshot`| Btrfs | Snapshot lifecycle, staged rollback, boot-once |
| `omni-security`| SecOps | TPM2 probing, UKI PE validation, SBAT auditing |
| `omni-fleet` | Swarm | Parallel SSH execution, telemetry aggregation, policy propagation |
| `omni-manifest`| Config | Desired-state drift detection and idempotent reconciliation |

*Extensible via `omni-plugin` — a POSIX-safe directory-based hook system with subshell isolation.*

---

## 🌱 The Omni-Seed Workflow

UOM is designed to be launched from any neutral Live Linux environment (SystemRescue, Alpine, Ubuntu, etc.):

1. **Boot** the target machine from any Live USB.
2. **Connect** to the network and start SSH: `passwd root && sshd`
3. **SSH in** from Android Termux or Desktop terminal.
4. **Execute the seed:**
   ```sh
   curl -sL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/scripts/omni-seed.sh | sh
   ```
5. **Adapt & Deploy:** UOM detects terminal width, initializes the state machine, downloads the monolith, and begins deployment.
6. **Survive:** If SSH drops or power fails, reconnect and re-run — UOM reads the durable ESP/Btrfs mirror and resumes seamlessly.

---

## 🧬 Validated Environments

| Distro | Libc | Init | Package Manager | Bootloader |
|---|---|---|---|---|
| 🏔️ Alpine 3.24 | musl | OpenRC | apk | GRUB |
| 🌀 Void | glibc | runit | xbps | systemd-boot |
| 🏹 Arch | glibc | systemd | pacman | systemd-boot |
| 🌀 Debian 12 | glibc | systemd | apt | GRUB |
| 🎨 Artix | glibc | OpenRC/runit/s6 | pacman | GRUB |
| 🌿 Chimera | musl | dinit | apk | — |

**Reference hardware:** HP Pavilion 15-n010tx (Intel HD 4000 + AMD Radeon HD 8670M muxless, degraded SATA cable baseline UDMA_CRC=5360, AC-only power, 4GB RAM).

---

## 🐛 Known Bug History (Lessons Learned)

These bugs were traced, fixed, and documented across M1–M20. They remain here as engineering lessons for contributors:

1. **`set --` clobbers `$@`** — used for version parsing in M12 launcher; destroyed the real subcommand arguments.
2. **BusyBox `sed`** does not interpret `\n` in replacement strings like GNU sed.
3. **BusyBox `dmesg`** has no `-w`/`--follow` flag; healer uses poll-diff mode.
4. **Stripping `_OMNI_ROOT=` lines** orphans multi-line guard clauses.
5. **Over-broad awk pattern** matches innocent lines like `[ -d . ]`.
6. **Top-level `return 1`** in sourced library files equals `exit 1` in a monolith.
7. **Terminal heredoc truncation** — always verify with `wc -l` + `tail -3` + `sh -n`.
8. **Unquoted `AGE(s)`** — parentheses are POSIX shell metacharacters; must be escaped.
9. **POSIX pipe-subshell trap** — piping into `while read` spawns a subshell; background jobs inside are orphaned from `wait`.
10. **`grep -c || printf 0` double-capture** — `grep -c` outputs `0` and exits `1` on no match, triggering the fallback and resulting in `"0\n0"`.
11. **`if "$handler"; then ... fi` exit swallow** — in POSIX sh, a false `if` with no `else` evaluates to `0`, swallowing the handler's non-zero exit code.
12. **`$$` in single-quoted heredocs** — `$$` is not expanded inside `<< 'EOF'`, breaking mock test paths.
13. **`mkfifo` + `&` process leaks** — named pipes and background jobs leak on Ctrl+C; use POSIX FD3 redirection (`3>file`) instead.

---

## 🚦 Quick Start

```sh
# Clone
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Detect this system
./bin/omni-detect

# Build the portable monolith (12 CLIs in one file)
./scripts/build-monolith.sh /tmp/omni.sh

# Deploy (dry-run by default)
./bin/omni-deploy plan --distro alpine --disk sda

# Run the full-stack regression gate (M1–M20)
./scripts/compat-check.sh
./scripts/test-m13-monolith.sh
./scripts/test-m14-security.sh
./scripts/test-m15-fleet.sh
./scripts/test-m16-state.sh
./scripts/test-m17-ui.sh
./scripts/test-m18-seed.sh
./scripts/test-m19-manifest.sh
./scripts/test-m20-livefeed.sh
```

---

## 📄 License

MIT — forged in the constraints of legacy hardware, engineered for the fleet of the future.
