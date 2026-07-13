<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20%2F%20BusyBox%20ash-000000?logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Tests-300%2B%20Assertions-brightgreen?logo=githubactions" alt="Tests">
  <img src="https://img.shields.io/badge/Release-v0.27.1-blueviolet?logo=github" alt="Release">
  <img src="https://img.shields.io/badge/License-MIT-green?logo=opensourceinitiative" alt="License">
  <img src="https://img.shields.io/badge/Cross--Libc-musl%20%E2%86%94%20glibc-orange?logo=linux" alt="Cross-Libc">
  <img src="https://img.shields.io/badge/AI-Augmented%20Fleet-SaaS%20Ready-blue?logo=openai" alt="AI">
</p>

<h1 align="center">🛰️ Universal Omni-Master (UOM)</h1>
<p align="center">
  <b>The Universal Bare-Metal Provisioning, Self-Healing & AI-Augmented Fleet Engine</b><br>
  <i>One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc. Any terminal. Any failure mode.</i>
</p>

---

## 🎯 What is Universal Omni-Master?

Universal Omni-Master (UOM) is a strictly POSIX-compliant, distribution-agnostic Linux deployment, orchestration, self-healing, and commercial SaaS framework. 

**Forged in the crucible of extreme hardware constraints**—specifically a degraded dual-boot HP Pavilion 15-n010tx featuring a muxless AMD dGPU, a failing SATA cable (stable UDMA_CRC baseline 5360), 4GB RAM, and a legacy BIOS without TPM2—UOM generalizes every hard-won fix into portable, fixture-tested abstractions.

Today, UOM is a **Class-1 Bare-Metal Provisioning Engine**. The entire framework—**17 CLI tools and 40+ library modules**—compiles into a single, self-extracting POSIX shell script (`omni-monolith.sh`). **No Python. No Git. No external dependencies.** Just `scp` and run.

---

## ✨ Core Capabilities

| Feature | Description |
| :--- | :--- |
| 🚀 **Universal Bootstrap** | Boot any Live ISO (SystemRescue, Alpine, Ubuntu), run `curl \| sh`, and UOM takes over. |
| 🧠 **Heuristic Crash-Resume** | Power fails mid-install? Re-run the seed script. The M16 State Machine resumes *exactly* where it left off. |
| 📱 **Adaptive TUI** | Detects `$COLUMNS`. Desktop (16:9) renders wide grids; Android Termux SSH (9:16) reflows to thumb-optimized vertical menus. |
| 🖥️ **Desktop & WM Profiles** | Telemetry-aware installation of Wayland/X11 compositors (Niri, Hyprland, Sway, HyDE, Quickshell) with Laplace-smoothed success scoring. |
| 🛡️ **STIG/CIS Compliance** | Idempotent enforcement of security baselines (e.g., `sshd_config` hardening) with NDJSON audit logging. |
| 🤖 **AI-Patcher** | Auto-rectifies deployment failures via local USB LLMs (`llama.cpp`) or ephemeral Cloud API keys, with `.bak` rollback safety. |
| 💼 **SaaS & OpenClaw Sync** | Free trial, pay-per-use, and subscription tiers. Anonymized telemetry bridges to external AI sales agents for automated upsell targeting. |
| 🩹 **Self-Healing Watchdog** | Parallel sub-daemons monitor `dmesg`, SMART, and services, auto-recovering from hardware degradation. |

---

## 🛠️ The 17-Tool CLI Surface

UOM compiles into a single monolith containing 17 distinct POSIX CLI entrypoints:

| Command | Domain | Purpose |
| :--- | :--- | :--- |
| `omni-detect` | **Discovery** | Hardware/software topology and baseline telemetry |
| `omni-service` | **Init** | Agnostic service control across 5 init backends |
| `omni-boot` | **Bootloader** | Inspect, install, and repair GRUB/systemd-boot |
| `omni-gpu` | **Graphics** | Hybrid switching and muxless dGPU policy enforcement |
| `omni-storage` | **Storage** | SMART/NVMe/Btrfs scrub and cable-watch policy engine |
| `omni-audit` | **Logging** | Unified structured NDJSON event log |
| `omni-deploy` | **Installer** | Full-disk partition, bootstrap, chroot, bootloader wiring |
| `omni-healer` | **Watchdog** | Parallel self-healing daemon (storage/services/GPU) |
| `omni-snapshot` | **Btrfs** | Snapshot lifecycle, staged rollback, boot-once |
| `omni-security` | **SecOps** | TPM2 probing, UKI PE validation, SBAT auditing |
| `omni-fleet` | **Swarm** | Parallel SSH execution, telemetry aggregation, swarm policies |
| `omni-manifest` | **Config** | Desired-state drift detection and idempotent reconciliation |
| `omni-saas` | **SaaS** | Tier switching, usage accounting, and credit enforcement |
| `omni-patcher` | **AI** | Heuristic auto-remediation and LLM telemetry |
| `omni-compliance`| **Compliance**| Fleet STIG/CIS enforcement and NDJSON audit |
| `omni-openclaw` | **Commercial**| Telemetry bridge for AI sales agent synchronization |
| `omni-desktop` | **Desktop** | Telemetry-aware profile engine for Wayland/X11 WMs & DEs |

*Extensible via `omni-plugin` — a POSIX-safe directory-based hook system with subshell isolation.*

---

## 🗺️ Milestone Roadmap

### ✅ Sealed: The Foundation & Intelligence (M1–M27.1)
| Phase | Milestones | Core Deliverables | Tags |
| :--- | :--- | :--- | :--- |
| **Foundation** | M1–M6 | Detection, Init, Boot, GPU, Storage, Audit | `v0.1.0`–`v0.6.0` |
| **Deployment** | M7–M12 | Installer, Healer, Snapshot, Rollback, Fish TUI | `v0.7.2`–`v0.12.0` |
| **Ecosystem** | M13–M15 | Monolith, SSH, Plugins, Security, Fleet | `v0.13.0`–`v0.15.0` |
| **Intelligence** | M16–M20 | State Machine, Adaptive TUI, Seed, Manifests, Livefeed | `v0.16.0`–`v0.20.0` |
| **Commercial** | M21–M26 | Manager, KVM, SaaS, AI-Patcher, Compliance, OpenClaw | `v0.21.0`–`v0.26.0` |
| **Desktop** | M27–M27.1 | WM/DE Profiles, Telemetry Dashboard, Hardening | `v0.27.0`–`v0.27.1` |

### 🚧 Planned: The Mobile & Quantum Horizon (M27.2+)
| Milestone | Vision |
| :--- | :--- |
| **M27.2** | **Installer + Postboot Integration**: `omni-deploy --desktop` flags, interactive SSH post-reboot verification (`DISPLAY_OK`). |
| **M27.3** | **OpenClaw Desktop Sync**: Commercial telemetry hooks for desktop profile adoption and package success rates. |
| **M28** | **Termux Native Polish**: Android haptic feedback (`termux-vibrate`), native notifications, and 9:16 swipe/key shortcuts. |
| **M29** | **Post-Quantum Crypto Hooks**: FIPS-140-3 compliant telemetry exports and quantum-safe fleet authentication. |
| **M30** | **Predictive Fleet Healing**: AI-driven hardware failure prediction based on aggregated UDMA_CRC and thermal telemetry. |

---

## 🌱 The Omni-Seed Workflow

UOM is designed to be launched from any neutral Live Linux environment:

1. **Boot** the target machine from any Live USB (SystemRescue, Alpine, Ubuntu).
2. **Connect** to the network and start SSH: `passwd root && sshd`
3. **SSH in** from Android Termux or a Desktop terminal.
4. **Execute the seed:**
   ```sh
   curl -sL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/scripts/omni-seed.sh | sh
   ```
5. **Adapt & Deploy:** UOM detects terminal width, initializes the state machine, downloads the monolith, and begins deployment.
6. **Survive:** If SSH drops or power fails, reconnect and re-run — UOM reads the durable ESP/Btrfs mirror and resumes seamlessly.

---

## 🧬 Validated Environments

| Distro | Libc | Init | Package Manager | Bootloader |
| :--- | :--- | :--- | :--- | :--- |
| 🏔️ **Alpine 3.24** | musl | OpenRC | apk | GRUB |
| 🌀 **Void** | glibc | runit | xbps | systemd-boot |
| 🏹 **Arch** | glibc | systemd | pacman | systemd-boot |
| 🌀 **Debian 12** | glibc | systemd | apt | GRUB |
| 🎨 **Artix** | glibc | OpenRC/runit/s6 | pacman | GRUB |
| 🌿 **Chimera** | musl | dinit | apk | — |

**Reference hardware:** HP Pavilion 15-n010tx (Intel HD 4000 + AMD Radeon HD 8670M muxless, degraded SATA cable baseline UDMA_CRC=5360, AC-only power, 4GB RAM).

---

## ⚖️ The UOM Manifesto (Immutable Engineering Rules)

1. 🐚 **POSIX-First**: `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms, zero `eval`, zero `set --`.
2. 🛡️ **Mutation Safety**: Any state-changing operation returns **126** when `OMNI_SYSROOT` is set.
3. 📉 **Baseline Telemetry**: Stable UDMA_CRC = 5360 is not a failure. Alerts only on negative deltas.
4. 🧩 **Monolithic Delivery**: 17 CLIs + 40+ libraries compile into one `scp`-able script.
5. 🧪 **Gate-Verified**: No milestone is tagged until its test suite AND every prior regression suite pass 100%.
6. 📝 **Rule #12**: Commit messages with `$`, `${}`, or backticks MUST use `git commit -F file`.

---

## 🐛 Known Bug History (18 Lessons Learned)

These bugs were traced, fixed, and documented. They remain as engineering lessons for contributors:

<details>
<summary><b>Click to expand the 18 POSIX & Shell Traps</b></summary>

1. `set --` clobbers `$@` (M12 launcher).
2. BusyBox `sed` doesn't interpret `\n` in replacement strings.
3. BusyBox `dmesg` has no `-w`/`--follow`; healer uses poll-diff.
4. Stripping `_OMNI_ROOT=` lines orphans multi-line guard clauses.
5. Over-broad `awk` pattern `/(^|[ \t])\.[ \t]+/` matches `[ -d . ]`.
6. Top-level `return 1` in sourced libraries = `exit 1` in monolith.
7. **Terminal heredoc truncation** (18 documented incidents) — always verify with `wc -l` + `tail -3` + `sh -n`.
8. Unquoted `AGE(s)` — parentheses are POSIX metacharacters.
9. POSIX pipe-subshell trap — piping into `while read` orphans background jobs.
10. `grep -c || printf 0` double-capture trap.
11. `if "$handler"; then` without `else` swallows non-zero exit codes.
12. `$$` in single-quoted heredocs is not expanded.
13. `mkfifo` + `&` process leaks on Ctrl+C (use FD3 redirection).
14. `stty size` overrides mocked `$COLUMNS` in seed layout hints.
15. `/dev/null` is not a regular file (`[ -f ]` fails).
16. Mock `PATH=$MOCKDIR` vs `$MOCKDIR/bin` mismatch.
17. Python `re.subn` `\1` backreference in replacement strings.
18. BusyBox `ash` nested quote landmine with markdown backticks in LLM prompts.

</details>

---

## 🚦 Quick Start

```sh
# Clone the repository
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Detect this system's hardware and baseline
./bin/omni-detect

# Build the portable monolith (17 CLIs in one file)
./scripts/build-monolith.sh /tmp/omni.sh

# Deploy (dry-run by default)
./bin/omni-deploy plan --distro alpine --disk sda

# Run the full-stack regression gate (M1–M27.1)
./scripts/compat-check.sh
```

---

## 📄 License

**MIT** — Forged in the constraints of legacy hardware, engineered for the AI-augmented fleet of the future.
