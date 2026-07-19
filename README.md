<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20BusyBox%20ash-000000?logo=gnubash&logoColor=white" alt="POSIX sh">
  <img src="https://img.shields.io/badge/Release-v0.34.0--rc1-blueviolet?logo=github" alt="Release">
  <img src="https://img.shields.io/badge/License-MIT-green?logo=opensourceinitiative" alt="License">
  <img src="https://img.shields.io/badge/Dual--Agent-Laptop+Phone-orange?logo=android" alt="Dual-Agent">
  <img src="https://img.shields.io/badge/Network-Drift%20Resilient-blue" alt="Network">
  <img src="https://img.shields.io/badge/Installer-Hardened-brightgreen" alt="Hardened">
</p>

<h1 align="center">UNIVERSAL OMNI-MASTER</h1>
<p align="center">
  <b>POSIX-Hardened AI Infrastructure OS for the Agentic Economy</b><br>
  <i>Dynamic model selection. Network drift resilience. Zero dependencies. Zero sudo.</i>
</p>

<p align="center">
  <a href="#-zero-trust-bootstrap">Bootstrap</a> ·
  <a href="#-dual-agent-orchestration">Dual-Agent</a> ·
  <a href="#-installer-hardening">Hardening</a> ·
  <a href="#-zen-loop-pipeline">Zen Loop</a> ·
  <a href="#%EF%B8%8F-architecture">Architecture</a> ·
  <a href="#-quick-start">Quick Start</a> ·
  <a href="#-phone-only-qemu">Phone VM</a> ·
  <a href="#-session-gate">Gate</a>
</p>

---

## Zero-Trust Bootstrap

One curl command. Auto-detects Termux/Android (ARM64) or Alpine Linux (x86_64).

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

| Component | What It Does |
|-----------|-------------|
| tmux + opencode | Dual-pane AI agent workspace |
| SSH key (id_ed25519_uom) | Dedicated zero-password key, UOM-managed block |
| SSH config | Managed aliases for tunnel/LAN discovery |
| Reverse tunnel | autossh-backed phone->laptop at port 31415 |
| nftables firewall | Drop-all-inbound except SSH + tunnel |

### Hardened Installer (`install/bootstrap-termux.sh`)

Patched with 5 critical fixes in [v0.34.0-rc1](docs/INSTALLER-TRUTH-MATRIX-20260719.md):

| Patch | Fix | Status |
|-------|-----|--------|
| A | SHA-safe clone: depth1 + fetch+checkout + tarball fallback | DONE |
| B | Dedicated key id_ed25519_uom with UOM-MANAGED markers | DONE |
| C | aarch64 QEMU policy: x86_64 removed, proot-distro default | DONE |
| D | Network gate: REPO_STATE=skipped-network on github unreachable | DONE |
| E | pkg update with 3-retry/timeout before install | DONE |

Profiles: `phone-relay` (default, ~25KB) and `phone-vm-agent` (VM profile, consent-gated).

```sh
sh install/bootstrap-termux.sh --check                        # Read-only preflight (default)
sh install/bootstrap-termux.sh --apply                        # Apply phone-relay install
sh install/bootstrap-termux.sh --apply --profile phone-vm-agent --allow-large-download --allow-vm --allow-opencode-install
```

Test harness: `sh tests/test-phone-bootstrap.sh` (72 assertions).

---

## Dual-Agent Orchestration

Laptop (Alpine) + Phone (Termux/Android) operate as a resilient AI agent pair connected via SSH. Git serves as the shared state store. When one node fails, the other takes over autonomously.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    UOM DUAL-AGENT SYSTEM                              │
│                                                                      │
│  ┌────────────────────┐          ┌────────────────────┐             │
│  │   LAPTOP (Primary) │◄────────►│   PHONE (Secondary)│             │
│  │   Alpine Linux     │  SSH     │   Termux / Android │             │
│  │   opencode         │  reverse │   opencode (Go)    │             │
│  │   dynamic IP       │  tunnel  │   QEMU guest VM    │             │
│  └────────┬───────────┘  31415   └────────┬───────────┘             │
│           │                               │                          │
│  ┌────────▼───────────────────────────────▼────────────────────┐    │
│  │              Git (Shared State Store)                       │    │
│  │  .uom-agent/state.json │ queue.json │ done.json             │    │
│  │  heartbeat/schema v2   │ multi-node  │ takeover_count       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  Mode     │ Trigger                  │ Who Runs opencode             │
│  ─────────┼──────────────────────────┼────────────────────────────── │
│  dual     │ Both reachable           │ Laptop primary                │
│  solo     │ Laptop unreachable       │ Phone autonomous              │
│  pending  │ >15 min (3 watchdog)     │ Manual confirm to dual        │
└─────────────────────────────────────────────────────────────────────┘
```

### Current Topology (Post-WiFi Switch, 2026-07-19)

| Node | Role | IP | User | Model | SDK |
|------|------|----|------|-------|-----|
| Phone2 | Hotspot/Gateway | 10.21.250.151 | u0_a217 | Redmi Note | 35 |
| Laptop | Primary agent | 10.21.250.90 | alpine | HP Pavilion | — |
| Phone1 | Secondary + QEMU host | 10.21.250.76 | u0_a608 | MI 8 | 35 |

- Phone2 is the WiFi hotspot. Laptop and Phone1 connect through it.
- Both phones reachable via direct SSH on port 8022 (no reverse tunnel needed on same subnet).
- Phone1 runs QEMU aarch64 guest VM for isolated AI workloads.
- Verified: `bin/uom-ssh-phone.sh` discovers and connects correctly after network switch.

See [docs/NET-ADAPT-WIFI-SWITCH-TEST-20260719.md](docs/NET-ADAPT-WIFI-SWITCH-TEST-20260719.md).

---

## Zen Loop Pipeline

Cloud-only code generation pipeline with dynamic model selection and network drift resilience. No ollama, no sudo, no hardcoded model names.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ZEN LOOP                                           │
│                                                                      │
│  ┌──────────┐   ┌───────────┐   ┌────────────┐   ┌──────────┐     │
│  │ Step 0   │──>│ Step 1-2  │──>│ Step 3-4   │──>│ Step 5-6 │     │
│  │ Pre-fl   │   │ tmux +    │   │ Network +  │   │ Generate │     │
│  │ checks   │   │ model     │   │ tunnel     │   │ + verify │     │
│  └──────────┘   └───────────┘   └────────────┘   └──────────┘     │
│                                                                      │
│  FREE MODEL POOL (4 models, auto-failover):                         │
│  1. deepseek-v4-flash-free                                          │
│  2. nemotron-3-ultra-free                                           │
│  3. north-mini-code-free                                            │
│  4. big-pickle                                                      │
│  Cache TTL: 300s │ Retry-After: respected │ History: 50             │
│                                                                      │
│  TUNNEL PORT: 31415 with drift resilience                           │
│  Network fingerprint: SHA256(gw + laptop_ip + phone)                │
│  On drift: port guardian rewrites SSH config, restarts              │
└─────────────────────────────────────────────────────────────────────┘
```

**6-Step Reconcile Pipeline** (`orchestrators/uom-reconcile.sh`):

| Step | Action |
|------|--------|
| 0 | Pre-flight: sshd, jq, opencode, routing, API reachability |
| 1 | Tmux guard: create `uom-hybrid` session with 4 windows |
| 2 | Cloud bootstrap: dynamic model selection (4-model pool) |
| 3 | Network + tunnel: fingerprint compute, port 31415 liveness |
| 4 | Port guardian: start sentinel, validate host hints |
| 5 | Zen agents: generator (dynamic model) + verifier (stub-aware) |
| 6 | Supervisor: status report, health monitoring |

---

## File Structure

```
universal-omni-master/
├── bin/                            # CLI entrypoints
│   ├── uom-ssh-phone.sh            # Drift-tolerant laptop->phone SSH
│   ├── uom-reverse-ssh.sh          # Phone->laptop reverse SSH tunnel
│   ├── uom-port-guardian.sh        # -> orchestrators/ (wrapper)
│   ├── uom-tmux-watchdog.sh        # -> orchestrators/ (wrapper)
│   ├── uom-status.sh               # Status dashboard
│   ├── uom-qemu-phone              # QEMU VM lifecycle manager
│   ├── uom-deploy-phone.sh         # Deploy scripts -> phone via SSH
│   ├── uom-phone-provision.sh      # proot-distro Debian provisioner
│   ├── uom-sync / uom-sync-status  # Git sync helpers
│   ├── uom-checkpoint.sh           # Session checkpoint/resume
│   ├── uom-statectl.sh             # State file management
│   └── omni-* (21 CLIs)            # Legacy monolith entrypoints
│
├── orchestrators/                  # Long-running daemon coordinators
│   ├── uom-reconcile.sh            # 6-step Zen Loop
│   ├── uom-port-guardian.sh        # Network drift sentinel
│   ├── uom-watchdog.sh             # Phone->laptop reachability
│   ├── uom-tmux-watchdog.sh        # Tmux session guardian
│   └── uom-solo-orchestrator.sh    # Phone-only fallback
│
├── scripts/                        # Pipelines, generators, verifiers
│   ├── uom-generator.sh            # Cloud code generator
│   ├── uom-verifier.sh             # Syntax/policy verifier
│   ├── uom-dryrun.sh               # Full dry-run test suite
│   ├── uom-lib.sh                  # Shared library (280 lines)
│   ├── uom-phone-bootstrap.sh      # Phone bootstrap wrapper
│   ├── uom-qemu-watchdog.sh        # QEMU health watchdog
│   └── test-*.sh (32)              # Milestone regression tests
│
├── install/                        # Bootstrap + installation
│   ├── bootstrap.sh                # Universal curl installer
│   ├── bootstrap-termux.sh         # Termux-specific (hardened)
│   ├── bootstrap-laptop.sh         # Laptop Alpine bootstrap
│   └── secrets.env.template        # API key template
│
├── tools/                          # Libraries + orchestration tools
│   ├── uom-model-rotate.sh         # Free model rotation
│   ├── uom-state-lib.sh            # POSIX state library
│   ├── uom-ip-discover.sh          # 5-method IP discovery
│   ├── uom-queue.sh                # Task queue manager
│   ├── uom-sync-loop.sh            # Bidirectional sync loop
│   ├── uom-phone-gen-loop.sh       # Phone generator loop
│   └── uom-feedback-aggregator.sh  # Verifier feedback loop
│
├── tests/                          # Test suites
│   ├── test-phone-bootstrap.sh     # 72-assertion installer test
│   ├── test-remote-llm.sh          # Remote LLM pipeline test
│   └── test-zen-loop-e2e.sh        # End-to-end Zen Loop test
│
├── docs/                           # 44 docs (architecture + reports)
│   ├── SCRIPT-CATALOG.md           # Complete script inventory
│   ├── ZEN-LOOP.md                 # Zen Loop architecture
│   ├── NETWORK-SCENARIOS.md        # 10 network scenarios
│   ├── SECURITY-BOUNDARIES.md      # Security policy
│   ├── PHONE-ONLY-OPERATIONS.md    # Daily phone ops
│   ├── INSTALLER-TRUTH-MATRIX-20260719.md  # Installer audit
│   ├── NET-ADAPT-WIFI-SWITCH-TEST-20260719.md  # WiFi test
│   ├── SESSION-GATE-20260719.md    # Current session gate
│   └── (36 more)
│
├── scripts/phone-shortcuts/        # Phone app shortcuts (12 scripts)
│   ├── 00-UOM-Status               # Status widget
│   ├── 30-UOM-Zen-Console          # Zen console launcher
│   ├── 50-UOM-Logs                 # Log viewer
│   └── tasks/10-UOM-Start          # Boot startup task
│
├── .uom-agent/                     # Runtime state (gitignored)
│   ├── state.json                  # Agent state machine
│   ├── queue.json                  # Task queue (PHASE13-17)
│   ├── runtime/                    # selected_model, net_fingerprint
│   └── logs/                       # Component logs
│
└── config/uom/                     # Configuration templates
    └── zen.env.example             # Zen Loop env vars
```

---

## Quick Start

### Bootstrap

```sh
# Any device (auto-detects platform):
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash

# Clone manually:
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master
```

### Phone (Termux) Installer

```sh
sh install/bootstrap-termux.sh --check                        # Read-only preflight
sh install/bootstrap-termux.sh --apply                        # Install phone-relay profile
sh install/bootstrap-termux.sh --apply --verify               # Install + validate
```

### Zen Loop

```sh
sh orchestrators/uom-reconcile.sh                  # Full 6-step pipeline
sh orchestrators/uom-reconcile.sh --reselect-model # Force model re-selection
sh tools/uom-model-rotate.sh select                # Pick best free model
sh tools/uom-model-rotate.sh status                # Show pool + history
scripts/uom-generator.sh "write a function"        # Cloud code generation
scripts/uom-verifier.sh path/to/file.sh            # Syntax verification
```

### Dual-Agent

```sh
# Laptop:
sh tools/uom-orch-laptop.sh

# Phone (run after bootstrap):
sh bin/uom-reverse-ssh.sh start    # Start reverse tunnel
sh bin/uom-port-guardian.sh start  # Start network sentinel

# Verify tunnel from laptop:
ssh -p 31415 u0_a608@127.0.0.1 "echo TUNNEL OK"
```

### Network Drift Resilience

```sh
sh bin/uom-port-guardian.sh start     # Background sentinel (tmux)
sh bin/uom-port-guardian.sh status    # Running? last-seen targets?
sh bin/uom-port-guardian.sh dryrun    # Self-test primitives
```

---

## Phone-Only QEMU

UOM runs entirely on a Xiaomi Mi 8 (dipper) inside a rootless QEMU aarch64 VM. No laptop required after initial setup.

```
Phone (Termux, Android 15, SDK 35)
  └─ QEMU rootless TCG (aarch64, no KVM)
       └─ Alpine 3.21 aarch64 (musl/OpenRC)
            ├─ opencode-zen-smart (curl wrapper, primary transport)
            ├─ opencode-zen-free (basic rotation)
            └─ UOM repo (~/src/universal-omni-master)
```

| Component | Version | Notes |
|-----------|---------|-------|
| Phone | Xiaomi Mi 8 (dipper) | crDroid Android 15, SDK 35 |
| Termux | Google Play 2026.06.21 | Same source for all plugins |
| QEMU | 10.2.1 | Rootless TCG, qemu-system-aarch64 |
| Alpine | 3.21 aarch64 | musl/OpenRC, hostname uom-phone-qemu |
| OpenCode | 1.18.3 (guest) | Native BLOCKED (IPv6), curl wrapper primary |

Key security: QEMU runs as Termux UID (never root), user-mode networking (no TAP/bridge), Termux private storage only. See [docs/SECURITY-BOUNDARIES.md](docs/SECURITY-BOUNDARIES.md).

---

## Session Gate (2026-07-19)

| Item | Status |
|------|--------|
| WiFi adapt dry-run | PASS — both phones reachable post-switch |
| Phone1 | UP (10.21.250.76, Mi 8, SDK 35, QEMU running) |
| Phone2 | UP (10.21.250.151, hotspot host, SDK 35) |
| Patch A (clone SHA) | DONE — depth1 + fetch + tarball fallback |
| Patch B (key name) | DONE — id_ed25519_uom, UOM-MANAGED markers |
| Patch C (arch policy) | DONE — x86_64 removed, proot-default on aarch64 |
| Patch D (network gate) | DONE — REPO_STATE=skipped-network on failure |
| Patch E (pkg update) | DONE — 3-retry with timeout |
| Branch sync | CLEAN — burn-in + release-gate fast-forward merged |
| Phone dry-run | PARTIAL — installer works post-wifi, SHA clone warns |
| Guardrails | PASS — all 4 guardrails functional |
| QEMU ISO downloads | NOT ENABLED this session |

Next: D3 unified guardrail CLI OR proot phone-agent profile testing OR merge review.

---

## Validated Environments

| Distro | Libc | Init | Status |
|--------|------|------|--------|
| Alpine 3.21 | musl | OpenRC | Primary (laptop + QEMU guest) |
| Termux (Android 15) | bionic | — | Primary (phone) |
| Void Linux | glibc | runit | Dual-boot |
| Debian 12 | glibc | systemd | Tested |

**Reference hardware:** HP Pavilion 15-n010tx (Intel i3-3217U, 4GB), Xiaomi Mi 8 (SDK 35), Redmi Note (SDK 35).

---

## Key Policies

| Policy | Rule |
|--------|------|
| **POSIX-First** | `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms |
| **No local LLMs** | Cloud-only via opencode --model. No ollama. |
| **Secrets** | Never in tracked files. Use `~/.config/uom/secrets.env` (mode 600). |
| **SSH keys** | Dedicated `id_ed25519_uom` only. UOM-MANAGED block in config. |
| **Git sync** | GitHub canonical. Pull = fetch + ff-only. No auto-conflict resolution. |
| **Singleton locks** | mkdir-based locks with PID validation + trap cleanup. |
| **Rate limits** | Honor Retry-After. Max 3 retries. Concurrency = 1. |

---

## License

**MIT** — Forged in the constraints of legacy hardware, engineered for the AI-augmented fleet of the future.

---

<p align="center">
  <i>Built with care on a failing SATA cable. Validated on 3 distros + 2 phones.</i><br>
  <a href="docs/SCRIPT-CATALOG.md">Script Catalog</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a> ·
  <a href="docs/ZEN-LOOP.md">Zen Loop</a> ·
  <a href="docs/PHONE-ONLY-OPERATIONS.md">Phone Ops</a>
</p>
