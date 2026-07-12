<p align="center">
  <img src="https://img.shields.io/badge/POSIX-sh%20%7C%20BusyBox%20Ash-blue?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Zero-Bashisms-red?style=for-the-badge" alt="Zero Bashisms">
  <img src="https://img.shields.io/badge/Milestone-M15%20Sealed%20%7C%20v0.15.0-success?style=for-the-badge" alt="Milestone">
  <img src="https://img.shields.io/badge/Cross--Libc-musl%20%E2%86%94%20glibc-purple?style=for-the-badge" alt="Cross-Libc">
</p>

<h1 align="center">🛰️ Universal Omni-Master (UOM)</h1>
<p align="center">
  <b>The Universal Bare-Metal Provisioning & Self-Healing Engine.</b><br>
  <i>One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc. Any terminal.</i>
</p>

---

## 🎯 What is this?

**Universal Omni-Master (UOM)** is a strictly POSIX-compliant, distribution-agnostic deployment and orchestration framework. Born from the extreme hardware constraints of taming a degraded dual-boot laptop (muxless AMD dGPU, failing SATA cable at UDMA_CRC baseline 5360, 4GB RAM), UOM has evolved from a localized survival tool into a **Class-1 Bare-Metal Provisioning Engine**.

UOM generalizes every hard-won hardware and software fix into a universal, testable abstraction. Today, it can bootstrap, deploy, manage, and heal Linux systems across the entire heterogeneous ecosystem. Whether you are deploying Alpine (musl/OpenRC), Void (glibc/runit), Arch (systemd), or Debian from a single **SystemRescue** Live ISO via an Android phone over SSH, UOM handles the cross-libc chroot, bootloader wiring, and crash-resume logic autonomously.

## ✨ The UOM Manifesto (Core Principles)

*   🐚 **POSIX-First & BusyBox-Safe:** `#!/bin/sh` everywhere. Zero bashisms (no `local`, no `**`, no arrays). Fish shell is strictly confined to the interactive TUI layer.
*   🧠 **Heuristic Crash-Resume:** Deployments are driven by a persistent state machine. If power fails or the network drops during a 2-hour `pacstrap`, re-running the seed script intelligently detects the broken session and resumes exactly where it left off.
*   📱 **Aspect-Ratio Adaptive TUI:** The interface dynamically reads `$COLUMNS`. Desktop (16:9) renders wide ASCII grids; Android Termux SSH (9:16 portrait) instantly reflows into stacked, thumb-optimized vertical menus with progressive log disclosure.
*   🛡️ **Mutation Safety Guard:** Any state-changing action hard-refuses (`exit 126`) when `OMNI_SYSROOT` is set, cleanly separating offline fixture testing from live bare-metal mutation.
*   📉 **Baseline-Relative Telemetry:** A stable non-zero SMART value (like UDMA_CRC = 5360) is not a failure. UOM alerts only on negative deltas from a learned baseline.
*   🧩 **Monolithic Delivery:** 11 CLIs and 40+ library modules compile into a single, self-contained, `scp`-able POSIX script. No Python, no Git, no external dependencies required on the target node.
*   🧬 **Cross-Libc Correctness:** Seamlessly bridges musl hosts to glibc targets via hardcoded `.interp` resolution (`/lib64/ld-linux-x86-64.so.2`) and efivarfs bridging for UEFI NVRAM writes.

---

## 🗺️ The Roadmap: From Abstraction to Bare-Metal

UOM's development is tracked through strict, gate-verified milestones. 

### Phase 1–3: Foundation, Healing & Fleet (Completed ✅)
| # | Milestone | Status | Core Deliverable |
|---|---|---|---|
| **M1** | 🔎 Hardware/Software Detection | ✅ Sealed | `omni-detect` (31 tests) |
| **M2** | ⚙️ Init/Service Abstraction | ✅ Sealed | 5 backends (systemd, OpenRC, runit, s6, dinit) |
| **M3** | 🥾 Bootloader Abstraction | ✅ Sealed | GRUB & systemd-boot wiring |
| **M4** | 🎮 GPU Policy Engine | ✅ Sealed | Intel/AMD/NVIDIA hybrid & muxless override |
| **M5** | 💾 Storage Telemetry | ✅ Sealed | SMART, NVMe, Btrfs scrub, cable-watch policy |
| **M6** | 🩺 Unified Diagnostics | ✅ Sealed | Structured NDJSON event auditing |
| **M7** | 🚀 Universal Deploy/Bootstrap | ✅ Sealed | Cross-libc chroot, pacstrap, debootstrap |
| **M8** | 🤖 Self-Healing Watchdog | ✅ Sealed | `omni-healer` daemon (dmesg poll-diff) |
| **M9** | 🔌 Healer Init Integration | ✅ Sealed | Per-init service units & enablement |
| **M10**| 📸 Btrfs Snapshot Lifecycle | ✅ Sealed | Create, prune, periodic hooks |
| **M11**| ⏪ Atomic Rollback | ✅ Sealed | Staged RW clone + boot-to-snapshot entries |
| **M12**| 🖥️ Fish TUI Control Plane | ✅ Sealed | `--no-config` isolated interactive dashboard |
| **M13**| 📦 Monolith & Fleet Transport | ✅ Sealed | POSIX bundler, SSH transport, Plugin API |
| **M14**| 🛡️ Security Hardening | ✅ Sealed | TPM2-LUKS, UKI validation, SBAT auditing |
| **M15**| 🌐 Fleet Orchestration | ✅ Sealed | Parallel SSH, Swarm policies, Multi-node TUI |

### Phase 4: The Universal Bare-Metal Blueprint (Active 🚧)
The current frontier transforms UOM into an unattended, unbreakable provisioning engine.

| # | Milestone | Vision & Deliverable |
|---|---|---|
| **M16** | 🧠 **Heuristic State Machine** | `src/deploy/state.sh` — Pure POSIX key=value state tracking. Enables idempotent step re-entry and mathematical crash-resume for multi-hour deployments. |
| **M17** | 📱 **Adaptive TUI Engine** | `src/tui/adaptive.sh` — Progressive disclosure and layout reflow. Detects Termux/SSH narrow terminals and switches to 9:16 portrait mode. |
| **M18** | 🌱 **Omni-Seed One-Liner** | `scripts/omni-seed.sh` — The `curl | sh` bootstrap. Boot *any* Live ISO (SystemRescue), connect to Wi-Fi, run the seed, and UOM chainloads the monolith to install the target OS. |
| **M19** | 📜 **Declarative Manifests** | `bin/omni-manifest` — Desired-state configuration engine. Idempotent apply with dry-run defaults. |
| **M20** | 📡 **Live Telemetry Feed** | Real-time deployment progress streaming. Split `tail -f` style output that adapts to the M17 portrait/landscape layout. |

---

## 🛠️ The Monolithic CLI Surface

UOM compiles into a single binary-like script (`omni-monolith.sh`) containing 11 distinct entrypoints. Each command is a thin CLI over a swappable backend layer that auto-selects the correct implementation via runtime discovery.

| Command | Domain | Role |
| :--- | :--- | :--- |
| `omni-detect` | Discovery | Hardware/software topology & baseline telemetry |
| `omni-service` | Init | Agnostic service control across 5 backends |
| `omni-boot` | Bootloader | Inspect, install, and repair GRUB/systemd-boot |
| `omni-gpu` | Graphics | Hybrid switching & muxless dGPU policy enforcement |
| `omni-storage` | Storage | SMART/NVMe/Btrfs scrub & cable-watch policy engine |
| `omni-audit` | Logging | Unified structured NDJSON event log |
| `omni-deploy` | Installer | Full-disk partition → bootstrap → chroot → boot |
| `omni-healer` | Watchdog | Parallel self-healing daemon (storage/services/GPU) |
| `omni-snapshot`| Btrfs | Snapshot lifecycle: create/list/prune/sweep/hooks |
| `omni-security`| SecOps | TPM2 probing, UKI PE validation, SBAT auditing |
| `omni-fleet` | Swarm | Parallel SSH execution, telemetry, & policy propagation |

*Extensible via `omni-plugin` (POSIX-safe directory-based hook system).*

---

## 🚀 The "Omni-Seed" Workflow (How it works)

UOM is designed to be launched from a neutral, powerful environment like **SystemRescue**.

1. **Boot** the target machine from the SystemRescue Live USB.
2. **Connect** to the network and start the SSH daemon (`passwd root && sshd`).
3. **SSH** from your Android phone (Termux) or Desktop.
4. **Execute** the seed:
   ```sh
   curl -sL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/scripts/omni-seed.sh | sh
   ```
5. **Adapt & Deploy:** UOM detects your terminal width, initializes the state machine, downloads the monolith, and begins deployment. 
6. **Survive:** If the SSH session drops or power fails, simply reconnect and re-run the `curl` command. UOM reads the state file and resumes seamlessly.

---

## 🧬 Validated Environments

UOM's fixture-driven testing matrix ensures reliability across the Linux spectrum:
*   🏔️ **Alpine** (musl · OpenRC · apk · doas)
*   🌀 **Void** (glibc · runit · xbps)
*   🏹 **Arch** (glibc · systemd · pacman)
*   🌀 **Debian** (glibc · systemd · apt · debootstrap)
*   🌿 **Chimera** (musl · dinit)
*   🛠️ **SystemRescue** (Arch-based Live ISO · Omni-Seed Host)
*   📦 **BusyBox-minimal** (Ash syntax validation)

---

## 🚦 Developer Quick Start

```sh
# Clone the repository
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Build the portable monolith
./scripts/build-monolith.sh /tmp/omni.sh

# Run the full-stack regression gate (M1–M15)
./scripts/compat-check.sh
./scripts/test-m13-monolith.sh
./scripts/test-m14-security.sh
./scripts/test-m15-fleet.sh
```

---

<p align="center">
  <i>Forged in the constraints of legacy hardware. Engineered for the fleet of the future.</i><br>
  <b>Universal Omni-Master</b>
</p>
```
