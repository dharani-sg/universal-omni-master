<p align="center">
  <img src="https://img.shields.io/badge/UNIVERSAL--OMNI--MASTER-v0.35.0--dev-6C3FBF?style=for-the-badge&logo=atom&logoColor=white" alt="UOM">
</p>

<h1 align="center">UNIVERSAL OMNI-MASTER</h1>

<p align="center">
  <strong>POSIX-Hardened Multi-Device AI Control Plane</strong><br>
  <em>Triple-node mesh · Free-model orchestration · Network drift recovery · Multi-swarm SaaS factory (Layer 3)</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Shell-POSIX%20sh-1E1E2E?style=flat-square&logo=gnubash&logoColor=white" alt="POSIX">
  <img src="https://img.shields.io/badge/Topology-Laptop%2BPhone1%2BPhone2-F59E0B?style=flat-square&logo=android&logoColor=white" alt="Triple">
  <img src="https://img.shields.io/badge/Guests-QEMU%20Alpine-3B82F6?style=flat-square&logo=qemu&logoColor=white" alt="QEMU">
  <img src="https://img.shields.io/badge/Models-Free--tier%20rotation-EF4444?style=flat-square&logo=openai&logoColor=white" alt="Models">
  <img src="https://img.shields.io/badge/Sync-Git%20bundles-10B981?style=flat-square&logo=git&logoColor=white" alt="Sync">
  <img src="https://img.shields.io/badge/Cost-ZERO-000000?style=flat-square&logo=dollar&logoColor=white" alt="Zero">
  <img src="https://img.shields.io/badge/License-MIT-22C55E?style=flat-square&logo=opensourceinitiative&logoColor=white" alt="MIT">
</p>

<p align="center">
  <a href="#what-uom-is">Overview</a> ·
  <a href="#system-layers">Layers</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#operating-modes">Modes</a> ·
  <a href="#zen-loop-pipeline">Zen Loop</a> ·
  <a href="#multi-swarm-saas-factory">SaaS Factory</a> ·
  <a href="#cli-surface">CLI</a> ·
  <a href="#roadmap">Roadmap</a> ·
  <a href="#non-negotiable-policies">Policies</a>
</p>

---

## What UOM Is

**Universal Omni-Master** turns any two POSIX devices — a laptop and a phone — into a resilient dual-agent AI system. Cloud-only. No local LLMs. No sudo. No API keys. No hardcoded IPs.

| Capability | How |
|:-----------|:----|
| 📱 **Phone Provisioning** | 3-stage hardened bootstrap chain → Termux relay or QEMU VM agent |
| 🔄 **Zen Loop Pipeline** | Cloud code generation with 4-model free rotation + 6-step reconcile |
| 🌐 **Network Drift Resilience** | 5-method IP discovery + port guardian + SHA256 fingerprint |
| 💻 **QEMU Workloads** | Rootless aarch64 VMs on phones for isolated AI processing |
| 🔀 **3-Node State Sync** | Git-based state machine across laptop, phone1, phone2 |
| 🏭 **SaaS Factory (L3)** | Multi-swarm workload layer: research → build → QA → deploy |

### What UOM Is NOT

- ❌ A CrewAI/LangChain app generator
- ❌ A no-code "Devin clone"
- ❌ An always-on paid-token SaaS factory
- ❌ A system that autonomously opens banks or KYC
- ❌ A promise of unattended production launches without human gates

---

## System Layers

```text
┌──────────────────────────────────────────────────────────────────┐
│ Layer 3 · Multi-Swarm SaaS Factory (planned / partial)           │
│ Research → Build → Quarantine QA → Deploy → Billing/Growth       │
├──────────────────────────────────────────────────────────────────┤
│ Layer 2 · Multi-Agent Control Plane (active)                     │
│ Trident / Zen Loop / leases / free-model rotation / gates        │
├──────────────────────────────────────────────────────────────────┤
│ Layer 1 · Device Mesh Runtime (active)                           │
│ Termux runit · reverse tunnels · widgets · QEMU guests           │
├──────────────────────────────────────────────────────────────────┤
│ Layer 0 · Host Platforms                                         │
│ Alpine laptop · Android 15 Termux · optional Alpine VMs          │
└──────────────────────────────────────────────────────────────────┘
```

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                        UNIVERSAL OMNI-MASTER v0.35.0-dev                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────┐       ┌─────────────────────────┐         │
│  │    LAPTOP (Primary)     │◄─────►│    PHONE1 (Secondary)   │         │
│  │    Alpine Linux         │ SSH   │    Termux / Android 15  │         │
│  │    opencode v1.18.3     │ 8022  │    QEMU aarch64 guest   │         │
│  │    Coordinator + Git    │       │    Worker + VM host     │         │
│  └───────────┬─────────────┘       └───────────┬─────────────┘         │
│              │                                  │                       │
│              │       ┌──────────────────┐       │                       │
│              │       │   PHONE2         │       │                       │
│              │       │   WiFi Hotspot   │       │                       │
│              │       │   Termux + SSH   │       │                       │
│              │       │   Worker node    │       │                       │
│              │       └──────────────────┘       │                       │
│              │                                  │                       │
│  ┌───────────▼──────────────────────────────────▼─────────────────┐    │
│  │             Git (Shared State Store via GitHub)                │    │
│  │  state.json (v2)  │  queue.json  │  done.json  │  bundles     │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │             Zen Loop Cloud Pipeline                            │    │
│  │  4-model free pool · auto-failover · Retry-After · $0 cost    │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Network Topology (Dynamic)

| Node | Role | Device | SDK | Status |
|:-----|:-----|:-------|:----|:-------|
| 🔴 Phone2 | Hotspot / Gateway | Redmi Note 23106RN0DA | 35 | 🟢 UP |
| 🔵 Laptop | Primary Agent + Git Hub | HP Pavilion 15-n010tx | — | 🟢 UP |
| 🟡 Phone1 | Secondary + QEMU Host | Xiaomi Mi 8 (dipper) | 35 | 🟡 DEGRADED |

> ⚠️ All IPs are **dynamic**. Use `tools/uom-ip-discover.sh` for discovery. Never hardcode.

---

## Quick Start

### 1. Deploy Phone Agent (One Curl Command)

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

Secure 3-stage chain:
```
curl pipe → bootstrap.sh (download-validate-exec)
         → bootstrap-termux.sh (phone-relay or phone-vm-agent)
         → SSH key + tmux + opencode CLI + repo clone
```

### 2. Provision Profiles

```sh
# Read-only preflight:
sh install/bootstrap-termux.sh --check

# Install phone-relay (default, ~25KB):
sh install/bootstrap-termux.sh --apply --verify

# Install VM profile (explicit consent required):
sh install/bootstrap-termux.sh --apply --profile phone-vm-agent \
  --allow-large-download --allow-vm --allow-opencode-install
```

### 3. Laptop Bootstrap (Alpine)

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-laptop.sh | sh
```

### 4. Run the Zen Loop

```sh
sh orchestrators/uom-reconcile.sh                    # Full 6-step pipeline
sh orchestrators/uom-reconcile.sh --reselect-model   # Force model re-selection
sh tools/uom-model-rotate.sh status                  # Show pool + history
scripts/uom-generator.sh "write a POSIX sh function" # Just generate
```

---

## Operating Modes

| Mode | When | Coordinator | Workers |
|:-----|:-----|:------------|:--------|
| 🟢 `SOLO` | Only laptop reachable | Laptop | Local only |
| 🔵 `DUAL_L_P1` | Laptop + Phone1 | Laptop | Phone1 host/VM |
| 🔵 `DUAL_L_P2` | Laptop + Phone2 | Laptop | Phone2 host/VM |
| 🟣 `TRIPLE` | Laptop + both phones | Laptop | Both phones |
| 🟡 `PEER_PHONES` | Phones only | Phone1 preferred | Phone2 |
| 🔴 `DEGRADED_PROXY` | Guest OpenCode broken | Laptop | Phone relays to laptop |

### Truthful Agent Labels

A phone that only relays OpenCode to the laptop is **NOT** an independent local LLM node.

| Label | Meaning |
|:------|:--------|
| `LOCAL_NATIVE` | Runs opencode natively on device |
| `LOCAL_PROOT` | Runs opencode inside proot-distro |
| `LOCAL_VM` | Runs opencode inside QEMU guest |
| `PROXY_TO_LAPTOP` | Relays inference to laptop via SSH |
| `BLOCKED` | Cannot run opencode (Android restriction) |

---

## Zen Loop Pipeline

Cloud-only code generation with dynamic model selection and network drift resilience.

```text
┌──────────┐   ┌───────────┐   ┌────────────┐   ┌──────────┐
│ Step 0   │──►│ Step 1-2  │──►│ Step 3-4   │──►│ Step 5-6 │
│ Pre-flight│   │ tmux +    │   │ Network +  │   │ Generate │
│ checks   │   │ model sel │   │ tunnel     │   │ + verify │
└──────────┘   └───────────┘   └────────────┘   └──────────┘
```

### 6-Step Reconcile

| Step | Action | Script |
|:-----|:-------|:-------|
| 0 | Pre-flight: sshd, jq, opencode, routing, API reachability | `orchestrators/uom-reconcile.sh` |
| 1–2 | Tmux guard + cloud bootstrap: create session, select model | `orchestrators/uom-reconcile.sh` |
| 3–4 | Network + tunnel: fingerprint, port 31415 liveness, guardian start | `orchestrators/uom-reconcile.sh` |
| 5–6 | Zen agents + supervisor: generator, verifier, status report | `scripts/uom-generator.sh`, `scripts/uom-verifier.sh` |

### Free Model Pool

| # | Model | Role | Auto-Failover |
|:--|:------|:-----|:--------------|
| 1 | `deepseek-v4-flash-free` | Primary | — |
| 2 | `nemotron-3-ultra-free` | Fallback 1 | ✓ |
| 3 | `north-mini-code-free` | Fallback 2 | ✓ |
| 4 | `big-pickle` | Fallback 3 | ✓ |

> Cache TTL: 300s · Retry-After: respected · History: 50 entries · Cost: **$0**

---

## Multi-Swarm SaaS Factory

### Positioning

The multi-swarm SaaS system is **Layer 3**. It uses UOM for isolated workers, long-running quarantine, free-model budgets, artifact handoff, deploy hooks, and recovery after network/device failure.

It does **NOT** replace UOM's mesh.

### Swarm Architecture (Adapted to UOM)

```text
[Swarm A: Discovery]
  Market pain, keyword demand, competitor scan
  UOM-native: OpenCode jobs + cached research artifacts
       │
       ▼ JSON idea packet
[Swarm B: Build]
  Architecture, backend, frontend, billing stubs
  UOM-native: OpenCode free-model builders on laptop/phone/VM workers
       │
       ▼ repo bundle / branch lease
[Swarm C: Quarantine QA]
  Unit + e2e + chaos + SAST for days/weeks
  UOM-native: existing verifier loops + long soak
       │
       ▼ signed QA certificate
[Swarm D: Launch Ops]
  Staging/prod deploy hooks, Stripe product setup, landing page
  UOM-native: omni-saas deploy adapters with human launch gate
       │
       ▼ human launch approval
```

### UOM-Native Implementation

| Swarm | SaaS Blueprint Tool | UOM Equivalent |
|:------|:--------------------|:---------------|
| Discovery | CrewAI + Apify + Semrush | OpenCode jobs + scrapers under network policy |
| Build | Devin / Aider / Claude paid | OpenCode free-model builders on mesh workers |
| QA | Playwright + LangGraph | Verifier loops + long soak + optional browser automation |
| Deploy | Vercel/AWS/Stripe directly | `omni-saas` adapters with explicit credentials + human gate |

### Mandatory SaaS Guardrails

| Guardrail | Rule |
|:----------|:-----|
| 💰 Money | Human configures master Stripe/legal entity first |
| 🔐 Secrets | Live only in `~/.config/uom/secrets.env` (mode 600) |
| 🤖 Models | Free-tier default; paid requires explicit override + budget cap |
| 🚫 Push | No autonomous `git push` to production without policy exception |
| 🛡️ Security | SAST/secrets scan before any launch package |
| ⏱️ Quarantine | Multi-day QA certificate required before production promote |
| 🌐 Network | Discovery scrapers rate-limited and policy-bound |
| 👤 Human Gate | Billing/domains/production launch need human approval |

### Example Idea Packet

```json
{
  "schema": "uom.saas.idea.v1",
  "title": "Offline invoice chaser for freelancers",
  "pain_evidence": ["forum_thread_ids", "search_demand"],
  "tam_band": "small_subscription",
  "suggested_stack": ["nextjs", "postgres", "stripe"],
  "constraints": {
    "max_monthly_token_budget_usd": 0,
    "require_free_models": true,
    "require_human_launch_approval": true
  }
}
```

### SaaS CLI

```sh
# Dry plan only:
sh bin/omni-saas plan --swarm research

# Gated pipeline (requires explicit allow flags):
sh bin/omni-saas run \
  --swarm full \
  --stage research,build,qa,deploy \
  --allow-network-research \
  --deny-paid-models \
  --require-human-launch-approval
```

---

## CLI Surface

### 🔧 Mesh / Control Plane

| Command | Location | Purpose |
|:--------|:---------|:--------|
| `uom-ssh-phone.sh` | `bin/` | Drift-tolerant laptop→phone SSH (5-method discovery) |
| `uom-reverse-ssh.sh` | `bin/` | Phone→laptop reverse tunnel (autossh-backed) |
| `uom-port-guardian.sh` | `orchestrators/` | Network drift sentinel (20s polling, SSH rewrite) |
| `uom-trident-v2.sh` | `orchestrators/` | Topology-aware triple orchestrator |
| `uom-reconcile.sh` | `orchestrators/` | 6-step Zen Loop (dynamic model + drift resilience) |
| `uom-solo-orchestrator.sh` | `orchestrators/` | Phone-only fallback when laptop unreachable |
| `uom-git-sync.sh` | `orchestrators/` | Hub/spoke Git bundle sync |

### 🧠 Zen Loop Tools

| Command | Location | Purpose |
|:--------|:---------|:--------|
| `uom-generator.sh` | `scripts/` | Cloud code generator (opencode stdin + 3-retry) |
| `uom-verifier.sh` | `scripts/` | Syntax/policy verifier (stub-aware, no LLM calls) |
| `uom-model-rotate.sh` | `tools/` | Free model rotation (4-model pool, Retry-After) |
| `uom-phone-gen-loop.sh` | `tools/` | Phone generator loop (PHASE14) |
| `uom-sync-loop.sh` | `tools/` | Bidirectional sync loop (PHASE15) |
| `uom-feedback-aggregator.sh` | `tools/` | Verifier feedback aggregation (PHASE16) |

### 🛠️ Infrastructure

| Command | Location | Purpose |
|:--------|:---------|:--------|
| `uom-state-lib.sh` | `tools/` | POSIX state library with atomic locking (v2) |
| `uom-ip-discover.sh` | `tools/` | 5-method IP discovery cascade |
| `uom-queue.sh` | `tools/` | Task queue manager |
| `uom-checkpoint.sh` | `bin/` | Session checkpoint/resume |
| `uom-status.sh` | `bin/` | Service status dashboard |

### 🏗️ Provisioning Engine (omni-* CLI)

| Command | Purpose |
|:--------|:--------|
| `omni-detect` | Hardware + OS detection |
| `omni-boot` | Boot config + GRUB management |
| `omni-deploy` | System deployment |
| `omni-gpu` | GPU driver management |
| `omni-storage` | Disk + LVM management |
| `omni-healer` | Self-healing repairs |
| `omni-snapshot` | Btrfs/ZFS snapshots |
| `omni-saas` | Multi-swarm SaaS factory (Layer 3) |
| `omni-desktop` | 11 WM/DE profiles |
| `omni-fleet` | Multi-node fleet management |
| `omni-compliance` | STIG/CIS compliance scanning |

> Full catalog: [`docs/SCRIPT-CATALOG.md`](docs/SCRIPT-CATALOG.md)

---

## Roadmap

### ✅ Sealed (Foundation → Phase 12)

| Phase | Milestones | Core Deliverables |
|:------|:-----------|:------------------|
| Foundation | M1–M6 | Detection, Init, Boot, GPU, Storage, Audit |
| Deployment | M7–M12 | Installer, Healer, Snapshot, Rollback, TUI |
| Ecosystem | M13–M15 | Monolith, SSH, Plugins, Security, Fleet |
| Intelligence | M16–M20 | State Machine, Adaptive TUI, Seed, Manifests |
| Commercial | M21–M26 | Manager, KVM, SaaS, AI-Patcher, Compliance |
| Desktop | M27 | 11 WM/DE Profiles, Telemetry, Postboot Verify |
| Dual-Agent | M28–M29 | IP Discovery, State Machine, Bootstrap, Solo Mode |
| Mobile | M30 | Project menu, tmux watchdog, port-guardian |
| Cloud + Zen | M30.5 | Cloud-only redirect, Zen Loop reconciler |
| Dynamic | M31 | Dynamic model selection, network fingerprinting |

### 🔄 Active Pipeline (PHASE13–PHASE17)

| Phase | ID | Description | Status |
|:------|:---|:------------|:-------|
| **PHASE13** | `ssh-remote-llm` | SSH-based remote LLM pipeline verification | ✅ PASS |
| **PHASE14** | `phone-generator-loop` | Phone generator picks up tasks + calls remote LLM | 🟡 PENDING |
| **PHASE15** | `bidirectional-sync` | Bidirectional sync of generated/verified state | 🟡 PENDING |
| **PHASE16** | `verifier-feedback-loop` | Laptop verifier processes phone code + writes feedback | 🟡 PENDING |
| **PHASE17** | `zen-loop-e2e` | End-to-end: phone generates → laptop verifies → phone receives | 🟡 PENDING |

### 🏭 SaaS Factory Track

| Phase | Deliverable | Status |
|:------|:------------|:-------|
| S0 | Idea packet schema + research job runner | 📋 Planned |
| S1 | Build swarm on OpenCode workers | 📋 Planned |
| S2 | Quarantine QA certificates + soak hooks | 🔶 Partial |
| S3 | Deploy adapters (Vercel/AWS/Docker) | 🔶 Hook-level |
| S4 | Stripe product/price automation (human master account) | 📋 Planned |
| S5 | Growth drafts + launch checklist | 📋 Planned |

### 🔮 Future Horizon

| Phase | Vision |
|:------|:-------|
| M33 | Post-Quantum: ML-KEM-768 hybrid KEX, ML-DSA host keys |
| M34 | Predictive AI: CRC regression, thermal telemetry, 60-min lookahead |
| M35 | Observability: eBPF kernel telemetry, bpftrace, Tetragon |
| M36 | Edge/IoT: Nix golden images, A/B OTA, dm-verity + Secure Boot |
| M37 | Confidential: AMD SEV-SNP / Intel TDX / ARM CCA |
| M38 | Protocol: MCP Server integration for AI assistants |
| M39–M43 | Bootloader, Federation, Power, OverlayFS, Trust |

---

## File Structure

```text
universal-omni-master/
├── bin/                     # CLI entrypoints (uom-*, omni-*)
├── orchestrators/           # Long-running control plane daemons
├── tools/                   # Libraries, discovery, guest toolbox, SaaS helpers
├── scripts/                 # Generators, verifiers, tests (32 test files)
├── install/                 # Bootstrap chains (3-stage hardened)
├── config/
│   ├── phone/               # Phone OpenCode/runtime profiles
│   ├── alpine-guest/        # Guest package manifests
│   └── saas/                # Multi-swarm schemas + stage contracts
├── docs/                    # Architecture + operations (45+ docs)
├── tests/                   # Test suites (72-assertion harness)
├── security/                # Hardening + firewall + hooks
├── artifacts/               # Local-only job outputs (gitignored)
└── .uom-agent/              # Runtime state (gitignored)
    ├── state.json           # Agent state machine (schema v2)
    ├── queue.json           # Task queue
    ├── done.json            # Completed tasks
    ├── runtime/             # selected_model, net_fingerprint
    ├── logs/                # Component logs
    └── locks/               # Singleton lockfiles (mkdir-based)
```

---

## Validated Environments

| Distro | Libc | Init | Role | Status |
|:-------|:-----|:-----|:-----|:-------|
| Alpine 3.21+ | musl | OpenRC | Laptop + QEMU guest | 🟢 Primary |
| Termux (Android 15) | bionic | — | Phone1 + Phone2 | 🟢 Primary |
| Void Linux | glibc | runit | Laptop (dual-boot) | 🔵 Tested |
| Debian 12 | glibc | systemd | — | 🔵 Tested |

### Hardware

| Device | Model | Role |
|:-------|:------|:-----|
| 💻 Laptop | HP Pavilion 15-n010tx (i3-3217U, 4GB) | Primary agent + Git hub |
| 📱 Phone1 | Xiaomi Mi 8 (dipper, SDK 35) | Secondary + QEMU host |
| 📱 Phone2 | Redmi Note 23106RN0DA (SDK 35) | Hotspot + worker |

---

## Non-Negotiable Policies

| Policy | Rule |
|:-------|:-----|
| 🐚 **POSIX-First** | `#!/bin/sh` everywhere. BusyBox ash-safe. Zero bashisms, zero `eval`. |
| ☁️ **No local LLMs** | Cloud-only via `opencode run --model`. No ollama. No local inference. |
| 🔐 **Secrets** | Never in tracked files. `~/.config/uom/secrets.env` (mode 600) only. |
| 🔑 **SSH keys** | Dedicated `id_ed25519_uom`. UOM-MANAGED block in config. |
| 🔄 **Git sync** | GitHub canonical. Pull = fetch + ff-only. No auto-conflict resolution. |
| 🔒 **Singleton locks** | mkdir-based locks with PID validation + trap cleanup. |
| ⏱️ **Rate limits** | Honor Retry-After. Max 3 retries. Concurrency = 1. |
| 💰 **Zero cost** | Free tier only. No API keys. No paid endpoints (unless explicit override). |
| 👤 **Human money gate** | Billing/domains/production launch need human approval. |
| 🌐 **Network truth** | Discovery > hardcoded IPs. Always. |
| 🏷️ **Honest labels** | Proxy is not local independence. Label truthfully. |

---

## Safety Model for SaaS Use

Before enabling multi-swarm SaaS jobs:

1. ✅ Mesh healthy: tunnels, discovery, free models, bundle sync
2. ✅ Secrets present only locally
3. ✅ Budget caps configured
4. ✅ Quarantine duration chosen
5. ✅ Deploy adapter credentials scoped
6. ✅ Human launch approval path defined

**Recommended first path:**
- Free-model research + build on laptop/phone mesh
- Long quarantine on staging only
- Human-approved launch
- No paid models until metrics justify them

---

## License

**MIT** — Built with care on a failing SATA cable. Validated on 3 distros + 2 phones.

<p align="center">
  <img src="https://img.shields.io/badge/Built_With-POSIX_sh-000000?style=for-the-badge&logo=gnubash&logoColor=white" alt="POSIX">
  <img src="https://img.shields.io/badge/Zero-Cost-10B981?style=for-the-badge&logo=dollar&logoColor=white" alt="Zero Cost">
  <img src="https://img.shields.io/badge/Zero-Dependencies-3B82F6?style=for-the-badge&logo=linux&logoColor=white" alt="Zero Deps">
  <img src="https://img.shields.io/badge/3_Distros-Tested-F59E0B?style=for-the-badge&logo=linux&logoColor=white" alt="3 Distros">
</p>

<p align="center">
  <a href="docs/SCRIPT-CATALOG.md">Script Catalog</a> ·
  <a href="docs/ROADMAP.md">Full Roadmap</a> ·
  <a href="docs/ZEN-LOOP.md">Zen Loop</a> ·
  <a href="docs/PHONE-ONLY-OPERATIONS.md">Phone Ops</a> ·
  <a href="docs/SECURITY-BOUNDARIES.md">Security</a> ·
  <a href="docs/SESSION-GATE-20260719.md">Session Gate</a>
</p>
