<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20%2F%20BusyBox%20ash-000000?logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Tests-300%2B%20Assertions-brightgreen?logo=githubactions" alt="Tests">
  <img src="https://img.shields.io/badge/Release-v0.29.0-blueviolet?logo=github" alt="Release">
  <img src="https://img.shields.io/badge/License-MIT-green?logo=opensourceinitiative" alt="License">
  <img src="https://img.shields.io/badge/Cross--Libc-musl%20%E2%86%94%20glibc-orange?logo=linux" alt="Cross-Libc">
  <img src="https://img.shields.io/badge/AI-Augmented%20Fleet-SaaS%20Ready-blue?logo=openai" alt="AI">
  <img src="https://img.shields.io/badge/Architecture-19%20CLIs%20%2F%2062%20Modules-brightgreen?logo=gnu" alt="Architecture">
  <img src="https://img.shields.io/badge/Init-OpenRC%20%7C%20systemd%20%7C%20runit%20%7C%20s6%20%7C%20dinit-informational" alt="Init">
  <img src="https://img.shields.io/badge/GPU-AMD%20%7C%20Intel%20%7C%20NVIDIA-informational" alt="GPU">
  <img src="https://img.shields.io/badge/Dual--Agent-Laptop+Phone-orange?logo=android" alt="Dual-Agent">
</p>

<h1 align="center">Universal Omni-Master (UOM)</h1>
<p align="center">
  <b>Resilient dual-agent AI orchestration across laptop + Android phone</b><br>
  <i>One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc. Any terminal. Any failure mode.</i>
</p>

<p align="center">
  <a href="#-what-is-universal-omni-master">Overview</a> •
  <a href="#-quick-bootstrap">Bootstrap</a> •
  <a href="#-dual-agent-architecture">Dual-Agent</a> •
  <a href="#-core-capabilities">Capabilities</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-the-19-tool-cli-surface">CLI Tools</a> •
  <a href="#-milestone-roadmap">Roadmap</a> •
  <a href="#-the-omni-seed-workflow">Quick Start</a> •
  <a href="#-validated-environments">Environments</a> •
  <a href="#-the-omni-manifesto">Manifesto</a> •
  <a href="#-license">License</a>
</p>

---

## 🎯 What is Universal Omni-Master?

Universal Omni-Master (UOM) is a **strictly POSIX-compliant, distribution-agnostic** Linux deployment, orchestration, self-healing, and commercial SaaS framework.

**Forged in the crucible of extreme hardware constraints** — specifically a degraded dual-boot HP Pavilion 15-n010tx featuring a muxless AMD dGPU, a failing SATA cable (stable UDMA_CRC baseline 5360), 4GB RAM, and a legacy BIOS without TPM2 — UOM generalizes every hard-won fix into portable, fixture-tested abstractions.

Today, UOM is a **Class-1 Bare-Metal Provisioning Engine**. The entire framework — **19 CLI tools and 62 library modules** — compiles into a single, self-extracting POSIX shell script (`omni-monolith.sh`). **No Python. No Git. No external dependencies.** Just `scp` and run.

> *"If your hardware is failing, your OS is wrong, your terminal is tiny, and your SSH connection drops every 5 minutes — UOM still boots."*

---

## 🚀 Quick Bootstrap

One curl command. Auto-detects Termux/Android (ARM64) or Alpine Linux (x86_64).

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

Sets up: tmux, SSH keys, opencode (Go build on phone, binary on Alpine), UOM repo, reverse tunnel, and tmux config.

---

## 🤖 Dual-Agent Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    UOM DUAL-AGENT SYSTEM                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐          ┌─────────────────────────┐   │
│  │   LAPTOP (Primary)   │◄───────►│    PHONE (Secondary)     │   │
│  │   Alpine 3.24        │  SSH    │    Termux / Android      │   │
│  │   opencode + omni    │reverse  │    opencode (Go build)   │   │
│  │   192.168.40.90      │ tunnel  │    192.168.40.207        │   │
│  └──────────┬──────────┘   18022  └──────────┬──────────────┘   │
│             │                                 │                 │
│  ┌──────────▼─────────────────────────────────▼──────────────┐  │
│  │              Git (Shared State Store)                     │  │
│  │  .uom-agent/state.json  │  queue.json  │  done.json       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Agent Modes:                                                    │
│  ┌──────────┬─────────────────────────┬──────────────────────┐   │
│  │ Mode     │ Trigger                 │ Who runs opencode    │   │
│  ├──────────┼─────────────────────────┼──────────────────────┤   │
│  │ dual     │ Both devices reachable  │ Laptop primary       │   │
│  │ phone-   │ Laptop unreachable      │ Phone only (solo)    │   │
│  │ solo     │ >15 min (3 watchdog)    │                      │   │
│  │ dual-    │ Laptop recovered from   │ Manual confirm to    │   │
│  │ pending  │ solo mode               │ switch back          │   │
│  └──────────┴─────────────────────────┴──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Watchdog (Phone-side)

Monitors laptop reachability every 60s. After 3 consecutive failures, triggers `phone-solo` mode autonomously. When laptop recovers, sets `dual-pending` — requires explicit confirmation to avoid split-brain.

---

## ✨ Core Capabilities

<table>
<tr>
<td width="50%">

### 🚀 Universal Bootstrap
Boot any Live ISO (SystemRescue, Alpine, Ubuntu), run `curl | sh`, and UOM takes over. Detects terminal width, initializes the state machine, downloads the monolith, and begins deployment.

### 🧠 Heuristic Crash-Resume
Power fails mid-install? Re-run the seed script. The **M16 State Machine** resumes *exactly* where it left off — no data loss, no partial installs, no manual intervention.

### 📱 Adaptive TUI
Detects `$COLUMNS`. Desktop (16:9) renders wide grids; Android Termux SSH (9:16) reflows to thumb-optimized vertical menus. The same codebase serves phone and workstation.

### 🖥️ Desktop & WM Profiles
Telemetry-aware installation of **11 Wayland/X11 compositors** (Niri, Hyprland, Sway, HyDE, Quickshell, Awesome, DWM, Fluxbox, Mango, Plasma, XFCE) with Laplace-smoothed success scoring.

</td>
<td width="50%">

### 🛡️ STIG/CIS Compliance
Idempotent enforcement of security baselines (e.g., `sshd_config` hardening) with NDJSON audit logging. Fleet-wide enforcement via `omni-compliance`.

### 🤖 AI-Patcher + Sentinel Mode
Auto-rectifies deployment failures via local USB LLMs (`llama.cpp`) or ephemeral Cloud API keys, with `.bak` rollback safety. Multi-model consensus for high-risk decisions. **Sentinel mode** (`--sentinel watch|suggest|auto`) enables continuous log tailing — the AI watches every line, catches errors before they cascade, and auto-applies fixes in real time during deployment.

### 💼 SaaS & OpenClaw Sync
Free trial, pay-per-use, and subscription tiers. Anonymized telemetry bridges to external AI sales agents for automated upsell targeting.

### 🩹 Self-Healing Watchdog
Parallel sub-daemons monitor `dmesg`, SMART, and services, auto-recovering from hardware degradation. 3-layer engine: Reactive → Predictive → Agentic.

</td>
</tr>
</table>

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    UNIVERSAL OMNI-MASTER (UOM)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ omni-detect│  │omni-deploy│  │omni-healer│  │omni-fleet │          │
│  │ Discovery │  │ Installer │  │ Watchdog │  │  Swarm   │          │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘          │
│        │              │              │              │                │
│  ┌─────▼──────────────▼──────────────▼──────────────▼────┐          │
│  │              62 POSIX Shell Library Modules             │          │
│  │  core/ boot/ gpu/ storage/ init/ deploy/ healer/      │          │
│  │  fleet/ snapshot/ security/ manifest/ saas/ ai/       │          │
│  │  compliance/ desktop/ plugin/ manager/ tui/ diag/     │          │
│  └───────────────────────┬───────────────────────────────┘          │
│                          │                                          │
│  ┌───────────────────────▼───────────────────────────────┐          │
│  │          5 Init Backends  │  3 GPU Vendors             │          │
│  │  openrc│systemd│runit│s6│dinit  AMD│Intel│NVIDIA       │          │
│  └───────────────────────────────────────────────────────┘          │
│                                                                     │
│  ┌───────────────────────────────────────────────────────┐          │
│  │         omni-monolith.sh (Single-File Delivery)       │          │
│  │    19 CLIs + 62 Libraries → One Self-Extracting Sh    │          │
│  └───────────────────────────────────────────────────────┘          │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  omni-tui     │  │  omni-seed    │  │  omni-plugin  │              │
│  │  Fish 4.x TUI │  │  Live Bootstrap│  │  Hook Engine  │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
└─────────────────────────────────────────────────────────────────────┘
```

### 🧬 Self-Healing Architecture

```
  ┌─────────────────────────────────────────────────┐
  │            omni-healer (Watchdog)                │
  │                                                  │
  │  ┌─────────────┐ ┌─────────────┐ ┌───────────┐ │
  │  │   Storage    │ │  Services   │ │    GPU    │ │
  │  │  Monitor     │ │  Monitor    │ │  Restore  │ │
  │  │  (SMART,     │ │  (init-     │ │  (driver  │ │
  │  │  CRC, btrfs) │ │  agnostic)  │ │  reload)  │ │
  │  └──────┬──────┘ └──────┬──────┘ └─────┬─────┘ │
  │         │                │               │       │
  │  ┌──────▼────────────────▼───────────────▼─────┐ │
  │  │           NDJSON Event Stream               │ │
  │  │     (structured, queryable, auditable)      │ │
  │  └────────────────────┬────────────────────────┘ │
  │                       │                          │
  │  ┌────────────────────▼────────────────────────┐ │
  │  │         AI-Patcher (LLM Engine)             │ │
  │  │  Local llama.cpp │ Cloud API │ Multi-model  │ │
  │  │  .bak rollback   │ Heuristic │ Consensus    │ │
  │  └─────────────────────────────────────────────┘ │
  └─────────────────────────────────────────────────┘
```

---

## 🛠️ The 19-Tool CLI Surface (+ Dual-Agent Tools)

UOM compiles into a single monolith containing **19 distinct POSIX CLI entrypoints**:

<table>
<tr>
<th>Command</th>
<th>Domain</th>
<th>Purpose</th>
</tr>
<tr>
<td><code>omni-detect</code></td>
<td><b>Discovery</b></td>
<td>Hardware/software topology and baseline telemetry (CPU, GPU, storage, power, seat model)</td>
</tr>
<tr>
<td><code>omni-service</code></td>
<td><b>Init</b></td>
<td>Agnostic service control across 5 init backends (OpenRC, systemd, runit, s6, dinit)</td>
</tr>
<tr>
<td><code>omni-boot</code></td>
<td><b>Bootloader</b></td>
<td>Inspect, install, and repair GRUB/systemd-boot with dual-stack support</td>
</tr>
<tr>
<td><code>omni-gpu</code></td>
<td><b>Graphics</b></td>
<td>Hybrid switching, muxless dGPU policy enforcement, driver load/unload</td>
</tr>
<tr>
<td><code>omni-storage</code></td>
<td><b>Storage</b></td>
<td>SMART/NVMe/Btrfs scrub, cable-watch policy engine, 30+ health subcommands</td>
</tr>
<tr>
<td><code>omni-audit</code></td>
<td><b>Logging</b></td>
<td>Unified structured NDJSON event log with JSON output format</td>
</tr>
<tr>
<td><code>omni-deploy</code></td>
<td><b>Installer</b></td>
<td>Full-disk partition, bootstrap, chroot, bootloader wiring, desktop integration, postboot verify</td>
</tr>
<tr>
<td><code>omni-healer</code></td>
<td><b>Watchdog</b></td>
<td>Parallel self-healing daemon (storage/services/GPU) with PID singleton</td>
</tr>
<tr>
<td><code>omni-snapshot</code></td>
<td><b>Btrfs</b></td>
<td>Snapshot lifecycle, staged rollback, boot-once, pre-txn hooks, periodic sweep</td>
</tr>
<tr>
<td><code>omni-security</code></td>
<td><b>SecOps</b></td>
<td>TPM2 probing, UKI PE validation, SBAT auditing, Secure Boot chain</td>
</tr>
<tr>
<td><code>omni-fleet</code></td>
<td><b>Swarm</b></td>
<td>Parallel SSH execution, telemetry aggregation, swarm policies, inventory</td>
</tr>
<tr>
<td><code>omni-manifest</code></td>
<td><b>Config</b></td>
<td>Desired-state drift detection and idempotent reconciliation (plan/apply)</td>
</tr>
<tr>
<td><code>omni-saas</code></td>
<td><b>SaaS</b></td>
<td>Tier switching, usage accounting, credit enforcement, license validation</td>
</tr>
<tr>
<td><code>omni-patcher</code></td>
<td><b>AI</b></td>
<td>Heuristic auto-remediation: analyze → LLM query → validate → apply with rollback</td>
</tr>
<tr>
<td><code>omni-compliance</code></td>
<td><b>Compliance</b></td>
<td>Fleet STIG/CIS enforcement and NDJSON audit (cis_level_1, stig_high profiles)</td>
</tr>
<tr>
<td><code>omni-openclaw</code></td>
<td><b>Commercial</b></td>
<td>Telemetry bridge for AI sales agent synchronization and upsell targeting</td>
</tr>
<tr>
<td><code>omni-desktop</code></td>
<td><b>Desktop</b></td>
<td>Telemetry-aware profile engine for 11 Wayland/X11 WMs & DEs with verify/dashboard</td>
</tr>
<tr>
<td><code>omni-manager</code></td>
<td><b>Control</b></td>
<td>Central control & expansion manager: audit-sync, module registry, snapshots</td>
</tr>
<tr>
<td><code>omni-tui</code></td>
<td><b>Interface</b></td>
<td>Deterministic POSIX launcher for Fish 4.x TUI (dashboard, installer, snapshots)</td>
</tr>
</table>

**Dual-Agent Tools:**
- `bin/uom-reverse-ssh.sh` — Reverse tunnel (phone→laptop) with autossh
- `orchestrators/uom-solo-orchestrator.sh` — Phone-only fallback when laptop is offline
- `orchestrators/uom-watchdog.sh` — Laptop reachability monitor
- `install/bootstrap.sh` — Universal curl installer (auto-detects platform)
- `security/uom-harden-ssh.sh` — Idempotent SSH hardening
- `security/uom-firewall.sh` — nftables ruleset
- `security/install-hooks.sh` — Pre-commit secret scanner

*Extensible via `omni-plugin` — a POSIX-safe directory-based hook system with subshell isolation.*

---

## 🗺️ Milestone Roadmap

### ✅ Sealed: The Foundation & Intelligence (M1–M29)

<table>
<tr>
<th>Phase</th>
<th>Milestones</th>
<th>Core Deliverables</th>
<th>Tags</th>
</tr>
<tr>
<td><b>🔧 Foundation</b></td>
<td>M1–M6</td>
<td>Detection, Init, Boot, GPU, Storage, Audit</td>
<td><code>v0.1.0</code>–<code>v0.6.0</code></td>
</tr>
<tr>
<td><b>🚀 Deployment</b></td>
<td>M7–M12</td>
<td>Installer, Healer, Snapshot, Rollback, Fish TUI</td>
<td><code>v0.7.2</code>–<code>v0.12.0</code></td>
</tr>
<tr>
<td><b>🌐 Ecosystem</b></td>
<td>M13–M15</td>
<td>Monolith, SSH, Plugins, Security, Fleet</td>
<td><code>v0.13.0</code>–<code>v0.15.0</code></td>
</tr>
<tr>
<td><b>🧠 Intelligence</b></td>
<td>M16–M20</td>
<td>State Machine, Adaptive TUI, Seed, Manifests, Livefeed</td>
<td><code>v0.16.0</code>–<code>v0.20.0</code></td>
</tr>
<tr>
<td><b>💼 Commercial</b></td>
<td>M21–M26</td>
<td>Manager, KVM, SaaS, AI-Patcher, Compliance, OpenClaw</td>
<td><code>v0.21.0</code>–<code>v0.26.0</code></td>
</tr>
<tr>
<td><b>🖥️ Desktop</b></td>
<td>M27–M27-C.1</td>
<td>WM/DE Profiles, Telemetry Dashboard, Hardening, Postboot Verify</td>
<td><code>v0.27.0</code>–<code>v0.27.4</code></td>
</tr>
<tr>
<td><b>🤖 Dual-Agent</b></td>
<td>M28–M29</td>
<td>Dynamic IP Discovery, State Machine, Bootstrap Installer, Solo Mode, Security Hardening</td>
<td><code>v0.28.0</code>–<code>v0.29.0</code></td>
</tr>
</table>

### 🔮 Planned: The Mobile, Quantum & Autonomous Horizon (M30–M42)

<table>
<tr>
<th>Milestone</th>
<th>Phase</th>
<th>Vision</th>
</tr>
<tr>
<td><b>M30</b></td>
<td>📱 Mobile</td>
<td><b>Termux Native Polish</b> — Android haptic feedback (<code>termux-vibrate</code>), native notifications, 9:16 swipe/key shortcuts, widget for quick deploy status.</td>
</tr>
<tr>
<td><b>M31</b></td>
<td>🔐 Post-Quantum</td>
<td><b>Post-Quantum Crypto Fleet Auth</b> — Auto-detect OpenSSH 9.9+ and configure <code>mlkem768x25519-sha256</code> as default KEX. Fleet-wide crypto inventory scan. ML-DSA host key readiness detection. Phased PQC migration: ML-KEM-768 hybrid → sntrup761 fallback → classical removal.</td>
</tr>
<tr>
<td><b>M32</b></td>
<td>🤖 Predictive AI</td>
<td><b>Predictive Fleet Healing</b> — AI-driven hardware failure prediction via linear regression on UDMA_CRC deltas, thermal telemetry, and SMART attributes. Causal root-cause analysis (PCMCI-inspired). 60-minute failure lookahead. Digital twin simulation before applying healing actions.</td>
</tr>
<tr>
<td><b>M33</b></td>
<td>📊 Observability</td>
<td><b>eBPF Kernel Telemetry</b> — Embedded bpftrace one-liners for provisioning workflow tracing. Tetragon TracingPolicy for security (detect unauthorized disk writes, boot chain tampering). Zero-overhead syscall observer feeding the AI healer. CO-RE for kernel-version portability.</td>
</tr>
<tr>
<td><b>M34</b></td>
<td>🏗️ Edge/IoT</td>
<td><b>Golden Image Builder</b> — Nix-based reproducible minimal base images. First-boot enrollment with provisioning key → real identity exchange. dm-verity + Secure Boot chain. A/B partition scheme with <code>systemd-sysupdate</code> for safe OTA. Batch provisioning (50+ simultaneous nodes).</td>
</tr>
<tr>
<td><b>M35</b></td>
<td>🛡️ Confidential</td>
<td><b>TEE-Aware Provisioning</b> — Detect AMD SEV-SNP / Intel TDX / ARM CCA hardware. Provision Trust Domains for sensitive workloads. Remote attestation for provisioned nodes. Encryption keys released only after attestation. Multi-vendor TEE abstraction behind unified API.</td>
</tr>
<tr>
<td><b>M36</b></td>
<td>🔌 Protocol</td>
<td><b>MCP Server Integration</b> — Embedded Model Context Protocol server so AI assistants (Claude, GPT, local LLMs) can query provisioning state, system health, and healing history via natural language. Plugin architecture for custom hardware sensors.</td>
</tr>
<tr>
<td><b>M37</b></td>
<td>🥾 Bootloader</td>
<td><b>Modern Boot Chain</b> — Default to systemd-boot for single-OS UEFI systems. BLS Type 1 boot entries for consistent kernel management across distros. Limine for multi-arch (ARM64, RISC-V). Crash-loop recovery with NVRAM state machine. UKI as first-class provisionable artifact.</td>
</tr>
<tr>
<td><b>M38</b></td>
<td>🌍 Federation</td>
<td><b>Fleet Federation</b> — Hub + daemon + dashboard architecture over gRPC. Prometheus/OpenMetrics export. mDNS auto-discovery (Ratatoskr pattern). Bifröst multi-site federation. Unprivileged by default. Threshold alerting with hysteresis.</td>
</tr>
<tr>
<td><b>M39</b></td>
<td>⚡ Power</td>
<td><b>Smart Power Management</b> — Auto-detect power source (AC/battery). TLP + power-profiles-daemon integration. CPU governor auto-tuning. Battery health dashboard with charge thresholds. RAPL/AmdPmu power consumption profiling. Laptop-specific provisioning profiles.</td>
</tr>
<tr>
<td><b>M40</b></td>
<td>🔄 OverlayFS</td>
<td><b>OS Layering Engine</b> — OverlayFS-based OS switching without container overhead. Host base system, swap guest OSes via SquashFS + writable overlay. Shared /home across distros with per-DE isolation. Machine-ID based boot entry isolation per distro.</td>
</tr>
<tr>
<td><b>M41</b></td>
<td>📝 Trust</td>
<td><b>Immutable Audit Trail</b> — Hash-chained, Merkle-rooted healing action log. Post-quantum signed audit entries. Boot trust-evidence logging to ESP. TPM-backed device identity with PKI certificate lifecycle. Dual-signature artifact verification (classical + PQ).</td>
</tr>
<tr>
<td><b>M42</b></td>
<td>🌐 Platform</td>
<td><b>Omni-Cloud SaaS GA</b> — Fleet management web dashboard with real-time maps. Multi-tenant isolation. REST/gRPC API for third-party integrations. Webhook-based alerting (Slack, Discord, PagerDuty). Usage-based billing with Stripe integration. SOC 2 compliance framework.</td>
</tr>
</table>

---

## 🌱 The Omni-Seed Workflow

UOM is designed to be launched from any neutral Live Linux environment:

```
┌─────────────────────────────────────────────────────────────────┐
│  1. BOOT        → Any Live USB (SystemRescue, Alpine, Ubuntu)  │
│  2. CONNECT     → passwd root && sshd                          │
│  3. SSH IN      → From Android Termux or Desktop terminal      │
│  4. SEED        → curl -sL .../omni-seed.sh | sh               │
│  5. ADAPT       → UOM detects terminal, state, downloads       │
│  6. DEPLOY      → Full-disk install with desktop integration   │
│  7. SURVIVE     → Power loss? Re-run. M16 state machine resumes│
└─────────────────────────────────────────────────────────────────┘
```

```sh
# The one-liner that starts everything
curl -sL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/scripts/omni-seed.sh | sh

# With AI-Patcher sentinel watching in real-time (auto-fix mode)
curl -sL .../omni-seed.sh | sh -s -- --sentinel auto

# Sentinel in suggest-only mode (reports but doesn't apply)
curl -sL .../omni-seed.sh | sh -s -- --sentinel suggest

# USB deployment with embedded sentinel
./omni-monolith.sh deploy --sentinel watch --distro alpine --disk sda
```

---

## 🧬 Validated Environments

<table>
<tr>
<th>Distro</th>
<th>Libc</th>
<th>Init</th>
<th>Package Manager</th>
<th>Bootloader</th>
<th>Status</th>
</tr>
<tr>
<td>🏔️ <b>Alpine 3.24</b></td>
<td>musl</td>
<td>OpenRC</td>
<td>apk</td>
<td>GRUB</td>
<td><code>✅ Primary</code></td>
</tr>
<tr>
<td>🌀 <b>Void Linux</b></td>
<td>glibc</td>
<td>runit</td>
<td>xbps</td>
<td>systemd-boot</td>
<td><code>✅ Dual-boot</code></td>
</tr>
<tr>
<td>🏹 <b>Arch Linux</b></td>
<td>glibc</td>
<td>systemd</td>
<td>pacman</td>
<td>systemd-boot</td>
<td><code>✅ Tested</code></td>
</tr>
<tr>
<td>🌀 <b>Debian 12</b></td>
<td>glibc</td>
<td>systemd</td>
<td>apt</td>
<td>GRUB</td>
<td><code>✅ Tested</code></td>
</tr>
<tr>
<td>🎨 <b>Artix Linux</b></td>
<td>glibc</td>
<td>OpenRC/runit/s6</td>
<td>pacman</td>
<td>GRUB</td>
<td><code>✅ Tested</code></td>
</tr>
<tr>
<td>🌿 <b>Chimera Linux</b></td>
<td>musl</td>
<td>dinit</td>
<td>apk</td>
<td>—</td>
<td><code>🧪 Experimental</code></td>
</tr>
</table>

**Reference hardware:** HP Pavilion 15-n010tx (Intel HD 4000 + AMD Radeon HD 8670M muxless, degraded SATA cable baseline UDMA_CRC=5360, AC-only power, 4GB RAM).

---

## ⚖️ The UOM Manifesto (Immutable Engineering Rules)

| # | Rule | Rationale |
| :--- | :--- | :--- |
| 1 | 🐚 **POSIX-First** | `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms, zero `eval`, zero `set --`. | Portable to any Linux, any init, any terminal. |
| 2 | 🛡️ **Mutation Safety** | Any state-changing operation returns **126** when `OMNI_SYSROOT` is set. | Prevents accidental destruction in dev/test. |
| 3 | 📉 **Baseline Telemetry** | Stable UDMA_CRC = 5360 is not a failure. Alerts only on negative deltas. | Hardware degradation is relative, not absolute. |
| 4 | 🧩 **Monolithic Delivery** | 19 CLIs + 62 libraries compile into one `scp`-able script. | Zero-dependency deployment from any host. |
| 5 | 🧪 **Gate-Verified** | No milestone is tagged until its test suite AND every prior regression suite pass 100%. | Regression prevention is non-negotiable. |
| 6 | 📝 **Rule #12** | Commit messages with `$`, `${}`, or backticks MUST use `git commit -F file`. | Shell expansion is a silent saboteur. |

---

## 🐛 Known Bug History (18 Lessons Learned)

These bugs were traced, fixed, and documented. They remain as engineering lessons for contributors:

<details>
<summary><b>Click to expand the 18 POSIX & Shell Traps</b></summary>

| # | Trap | Milestone |
| :--- | :--- | :--- |
| 1 | `set --` clobbers `$@` | M12 |
| 2 | BusyBox `sed` doesn't interpret `\n` in replacement strings | M7 |
| 3 | BusyBox `dmesg` has no `-w`/`--follow`; healer uses poll-diff | M8 |
| 4 | Stripping `_OMNI_ROOT=` lines orphans multi-line guard clauses | M9 |
| 5 | Over-broad `awk` pattern matches `[ -d . ]` | M10 |
| 6 | Top-level `return 1` in sourced libraries = `exit 1` in monolith | M13 |
| 7 | **Terminal heredoc truncation** (18 documented incidents) | M17 |
| 8 | Unquoted `AGE(s)` — parentheses are POSIX metacharacters | M14 |
| 9 | POSIX pipe-subshell trap — piping into `while read` orphans bg jobs | M8 |
| 10 | `grep -c \|\| printf 0` double-capture trap | M16 |
| 11 | `if "$handler"; then` without `else` swallows non-zero exit codes | M15 |
| 12 | `$$` in single-quoted heredocs is not expanded | M17 |
| 13 | `mkfifo` + `&` process leaks on Ctrl+C (use FD3 redirection) | M21 |
| 14 | `stty size` overrides mocked `$COLUMNS` in seed layout hints | M18 |
| 15 | `/dev/null` is not a regular file (`[ -f ]` fails) | M7 |
| 16 | Mock `PATH=$MOCKDIR` vs `$MOCKDIR/bin` mismatch | M16 |
| 17 | Python `re.subn` `\1` backreference in replacement strings | M13 |
| 18 | BusyBox `ash` nested quote landmine with markdown backticks in LLM prompts | M24 |

</details>

---

## 🚦 Quick Start

```sh
# Quick bootstrap (any device)
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash

# Clone the repository
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Detect this system's hardware and baseline
./bin/omni-detect

# Build the portable monolith (19 CLIs in one file)
./scripts/build-monolith.sh /tmp/omni.sh

# Deploy (dry-run by default)
./bin/omni-deploy plan --distro alpine --disk sda

# Deploy with AI-Patcher sentinel watching in real-time
./bin/omni-deploy plan --distro alpine --disk sda --sentinel auto

# Run the full-stack regression gate (M1–M27.1)
./scripts/compat-check.sh
```

### Dual-Agent Quick Start

```sh
# On laptop (Alpine):
cd ~/src/universal-omni-master
sh bin/uom-reverse-ssh.sh  # wait for phone to connect

# On phone (Termux):
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
# or manually:
cd ~/src/universal-omni-master
bash bin/uom-reverse-ssh.sh  # opens tunnel to laptop

# Verify tunnel from either device:
ssh -o ConnectTimeout=5 127.0.0.1 -p 18022 echo "TUNNEL OK"
```

---

## 📂 Repository Structure

```
universal-omni-master/
├── bin/                    # 19 CLI entrypoints
├── src/                    # 62 library modules
│   ├── ai/                 #   AI patcher engine
│   ├── boot/               #   GRUB + systemd-boot
│   ├── compliance/         #   STIG/CIS enforcement
│   ├── core/               #   detect, config, logging, utils, priv
│   ├── deploy/             #   installer (18 modules)
│   ├── desktop/            #   11 WM/DE profiles + telemetry
│   ├── diag/               #   12 diagnostic subsystems
│   ├── fleet/              #   swarm, parallel, telemetry
│   ├── gpu/                #   AMD, Intel, NVIDIA
│   ├── healer/             #   watchdog (storage, services, GPU)
│   ├── init/               #   5 init backends
│   ├── manager/            #   central control
│   ├── manifest/           #   drift detection
│   ├── plugin/             #   hook engine
│   ├── saas/               #   metering + openclaw
│   ├── security/           #   TPM2, UKI, SBAT
│   ├── snapshot/           #   btrfs lifecycle + hooks
│   ├── storage/            #   SMART, cablewatch, btrfs, fs
│   └── tui/                #   Fish 4.x dashboard
├── scripts/                # 38 build/test/deploy scripts
├── config/                 # hardware profiles + snapshot config
├── sandbox/                # fixture sysroots (5 distros)
├── docs/                   # AI-HANDOFF, ROADMAP, PHONE-SETUP, SECRETS
├── install/                # Bootstrap installers (detect-and-dispatch, termux, laptop)
├── orchestrators/          # Dual-agent orchestrators (solo, watchdog)
├── security/               # SSH hardening, firewall, pre-commit hooks
└── tests/                  # BATS fixtures
```

---

## 🤝 Contributing

UOM is built on **immutable engineering rules**. Before contributing:

1. **Read the Manifesto** — POSIX-first, mutation safety, gate-verified.
2. **Run the regression gate** — `./scripts/compat-check.sh` must pass 100%.
3. **No bashisms** — `#!/bin/sh` everywhere. BusyBox ash-safe.
4. **No comments unless asked** — Code is self-documenting.
5. **Rule #12** — Shell variables in commit messages → `git commit -F file`.

---

## 📄 License

**MIT** — Forged in the constraints of legacy hardware, engineered for the AI-augmented fleet of the future.

---

## ⚠️ Known Issues (v0.29.0)

- **Reverse tunnel (18022):** DOWN until phone runs `bash ~/bin/uom-reverse-ssh.sh` — bootstrap installs the script automatically
- **SATA CRC:** 5361 (degraded cable) — avoid large writes to sda4 (`/`)
- **sda4 disk:** 85% used — monitor for space exhaustion
- **Phone opencode:** npm rejected on ARM64 — uses `go install` instead
- **doas TTY requirement:** Never invoke root commands from opencode subprocess — always run manually from terminal
- **Pre-commit hook:** Installed via `sh security/install-hooks.sh` — blocks accidental secret commits

<!-- last-sync: 2026-07-17T07:35:34Z -->

---

<p align="center">
  <i>Built with ❤️ on a failing SATA cable. Proven on 6 distros. Designed for the next decade.</i>
</p>
