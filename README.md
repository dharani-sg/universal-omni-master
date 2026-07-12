 🛰️ Universal Omni-Master (UOM)

**The Universal Bare-Metal Provisioning & Self-Healing Engine**

![POSIX sh](https://img.shields.io/badge/shell-POSIX%20sh-success?logo=gnubash&logoColor=white)
![BusyBox](https://img.shields.io/badge/BusyBox-ash--safe-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://img.shields.io/badge/gates-M1--M15%20green-brightgreen)
![Release](https://img.shields.io/badge/release-v0.15.0-blueviolet)
![Cross-Libc](https://img.shields.io/badge/cross--libc-musl%E2%86%92glibc-orange)

> One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc. Any terminal.

---

## 🎯 What is Universal Omni-Master?

Universal Omni-Master (UOM) is a strictly POSIX-compliant, distribution-agnostic Linux deployment, orchestration, and self-healing framework. It was forged from the extreme constraints of a degraded dual-boot HP Pavilion 15-n010tx — muxless AMD dGPU, failing SATA cable (stable UDMA_CRC baseline 5360), 4GB RAM, mixed musl/glibc environments — and generalizes every hard-won fix into portable, testable abstractions.

Today, UOM can bootstrap, deploy, manage, heal, snapshot, roll back, and fleet-orchestrate Linux systems across the entire heterogeneous ecosystem. Whether deploying Alpine from a SystemRescue Live ISO via an Android phone over SSH, or managing a fleet of 50 Arch servers from a Fish TUI dashboard, UOM handles cross-libc chroot resolution, bootloader wiring, init-system service enablement, and crash-resume logic autonomously.

The entire framework — 11 CLIs and 40+ library modules — compiles into a **single self-extracting POSIX shell script** (`omni-monolith.sh`). No Python, no Git, no external dependencies required on the target node. Just `scp` and run.

---

## ✨ The UOM Manifesto (Core Principles)

| Principle | Implementation |
|---|---|
| 🐚 **POSIX-First** | `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms (`local`, `**`, arrays, `eval` are all banned). Fish is confined to the interactive TUI only. |
| 🛡️ **Mutation Guard** | Any state-changing operation returns exit **126** when `OMNI_SYSROOT` is set, cleanly separating fixture testing from live bare-metal mutation. |
| 📉 **Baseline Telemetry** | A stable non-zero SMART value (like UDMA_CRC = 5360) is not a failure. UOM alerts only on negative deltas from a stored baseline. |
| 🧩 **Monolithic Delivery** | Clean per-domain modules build into one portable, self-extracting, self-verifying script. |
| ⚖️ **Cross-Libc Correctness** | Bridges musl hosts to glibc targets via hardcoded `.interp` resolution and `efivarfs` bridging for UEFI NVRAM writes. |
| 🩹 **Graceful Degradation** | Security modules (TPM2/UKI/SBAT) detect missing hardware and degrade to structured audit-only warnings. They never hard-fail on legacy machines. |
| 🧪 **Gate-Verified** | No milestone is tagged until its test suite AND every prior regression suite pass 100%. All 15 milestones carry green gates (200+ automated assertions). |

---

## 🗺️ Milestone Roadmap

### Phase 1–3: Foundation, Healing & Fleet (✅ SEALED at v0.15.0)

| # | Milestone | Deliverable |
|---|---|---|
| **M1** | 🔎 Hardware/Software Detection | `omni-detect` — multi-distro fixture-based discovery (31 tests) |
| **M2** | ⚙️ Init/Service Abstraction | `omni-service` — systemd, OpenRC, runit, s6, dinit (16 tests) |
| **M3** | 🥾 Bootloader Abstraction | `omni-boot` — GRUB + systemd-boot wiring (14 tests) |
| **M4** | 🎮 GPU Policy Engine | `omni-gpu` — Intel/AMD/NVIDIA hybrid, muxless dGPU override (22 tests) |
| **M5** | 💾 Storage Telemetry | `omni-storage` — SMART/NVMe/Btrfs scrub, cable-watch, baseline-relative |
| **M6** | 🩺 Unified Diagnostics | `omni-audit` — structured NDJSON event logging |
| **M7** | 🚀 Universal Installer | `omni-deploy` — cross-libc chroot, pacstrap -K, debootstrap, rollback protocol (21 tests) |
| **M8** | 🤖 Self-Healing Daemon | `omni-healer` — parallel sub-daemons; BusyBox dmesg poll-diff fallback (13 tests) |
| **M9** | 🔌 Init Service Integration | Per-init service units for omni-healer across all 5 init systems (40 tests) |
| **M10**| 📸 Btrfs Snapshot Lifecycle | `omni-snapshot` — create/list/prune/periodic/hooks with per-category retention |
| **M11**| ⏪ Atomic Rollback | Staged RW clone + boot-to-snapshot entries; never uses `btrfs set-default` |
| **M12**| 🖥️ Fish TUI Control Plane | `omni-tui` — deterministic `--no-config` isolated dashboard, installer wizard (14 tests) |
| **M13**| 📦 Monolith & Fleet Transport | POSIX bundler, SSH remote transport, subshell-isolated plugin hooks |
| **M14**| 🛡️ Security Hardening | `omni-security` — TPM2-LUKS probing, UKI PE validation, SBAT auditing (17 tests) |
| **M15**| 🌐 Fleet Orchestration | `omni-fleet` — POSIX batch-parallel SSH, NDJSON telemetry, swarm policies (29 tests) |

### Phase 4: The Universal Bare-Metal Blueprint (🚧 ACTIVE)

| # | Milestone | Vision |
|---|---|---|
| **M16** | 🧠 **Heuristic State Machine** | `src/deploy/state.sh` — pure POSIX key=value state tracking for crash-resume. If power fails during a 2-hour `pacstrap`, re-running the seed script resumes exactly where it left off. |
| **M17** | 📱 **Adaptive TUI Engine** | Layout reflow based on `$COLUMNS`. Desktop (16:9) renders wide ASCII grids; Android Termux SSH (9:16 portrait) switches to stacked vertical menus optimized for thumb input. |
| **M18** | 🌱 **Omni-Seed One-Liner** | `curl -sL .../omni-seed.sh \| sh` — works from ANY live ISO. Downloads the monolith, initializes the state machine, launches deployment. SSH drop + re-run = seamless resume. |
| **M19** | 📜 **Declarative Manifests** | `omni-manifest` — desired-state configuration engine with idempotent apply and dry-run defaults. |
| **M20** | 📡 **Live Telemetry Feed** | Real-time deployment progress streaming that adapts to the M17 portrait/landscape layout. |

---

## 🛠️ The 11-Tool CLI Surface

UOM compiles into a single self-extracting script (`omni-monolith.sh`) containing 11 distinct POSIX CLI entrypoints:

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
6. **Survive:** If SSH drops or power fails, reconnect and re-run — UOM reads the state file and resumes seamlessly.

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

**Reference hardware:** HP Pavilion 15-n010tx (Intel HD 4000 + AMD Radeon HD 8670M muxless, degraded SATA cable at UDMA_CRC baseline 5360, AC-only power, 4GB RAM).

---

## 🐛 Known Bug History (Lessons Learned)

These bugs were traced, fixed, and documented across M1–M15. They remain here as engineering lessons for contributors:

1. **`set --` clobbers `$@`** — used for version parsing in M12 launcher; destroyed the real subcommand arguments.
2. **BusyBox `sed`** does not interpret `\n` in replacement strings like GNU sed.
3. **BusyBox `dmesg`** has no `-w`/`--follow` flag; healer uses poll-diff mode.
4. **Stripping `_OMNI_ROOT=` lines** orphans multi-line guard clauses.
5. **Over-broad awk pattern** matches innocent lines like `[ -d . ]`.
6. **Top-level `return 1`** in sourced library files equals `exit 1` in a monolith.
7. **Terminal heredoc truncation** — always verify with `wc -l` + `tail -3` + `sh -n`.
8. **Unquoted `AGE(s)`** — parentheses are POSIX shell metacharacters; must be escaped.
9. **POSIX pipe-subshell trap** — piping into `while read` spawns a subshell; background jobs inside are orphaned from `wait`.

---

## 🚦 Quick Start

```sh
# Clone
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Detect this system
./bin/omni-detect

# Build the portable monolith (11 CLIs in one file)
./scripts/build-monolith.sh /tmp/omni.sh

# Run the full-stack regression gate (M1–M15)
./scripts/compat-check.sh
./scripts/test-m13-monolith.sh
./scripts/test-m14-security.sh
./scripts/test-m15-fleet.sh
```

---

## 📄 License

MIT — forged in the constraints of legacy hardware, engineered for the fleet of the future.
