# UOM Roadmap — Research-Backed Strategic Refactor

> **Generated:** 2026-07-21  
> **Source:** Deep Research Pipeline (GitHub API, PyPI stats, OpenRouter model list, n8n/Dify pricing)  
> **Monetization prices in INR (₹) primary, SGD ($) secondary, USD ($) reference**  
> **Target market:** India (hometown) + Singapore (workplace)  
> **Version:** v0.35.0-dev

---

## 1. Project Identity & Layer Status

**Universal Omni-Master (UOM)** is a POSIX-hardened, multi-device AI control plane that transforms consumer hardware into a sovereign edge mesh. Current layer readiness:

| Layer | Name | Status Badge | Description |
|:------|:-----|:-------------|:------------|
| **L0** | Host Platforms | <img src="https://img.shields.io/badge/L0-STABLE-green?style=flat-square" alt="Stable"> | HP Pavilion laptop + Android 15 Termux + QEMU aarch64 guests |
| **L1** | Device Mesh Runtime | <img src="https://img.shields.io/badge/L1-STABLE-green?style=flat-square" alt="Stable"> | Termux runit, reverse SSH tunnels, port guardian, Git bundle sync |
| **L2** | Multi-Agent Control Plane | <img src="https://img.shields.io/badge/L2-STABLE-green?style=flat-square" alt="Stable"> | Trident orchestrator, Zen Loop, free-model rotation, gates |
| **L3** | Multi-Swarm SaaS Factory | <img src="https://img.shields.io/badge/L3-BETA-yellow?style=flat-square" alt="Beta"> | S0-S5 pipeline under active construction — see §8 |

**Current hardware inventory:** HP Pavilion 15-n010tx — i3-3217U, 4GB RAM, HDD (failing SATA) · Xiaomi Mi 8 (dipper, SD845, SDK 35) — secondary QEMU host · Redmi Note 23106RN0DA (SDK 35) — hotspot/gateway

---

## 2. Monetization Strategy

### 2.1 Revenue Tiers

Revenue sources are modeled based on IndieHackers solo-dev SaaS benchmarks [ESTIMATE: IndieHackers solo OSS benchmark 2024-2025] and India-first pricing (PPP adjusted):

| Phase | Label | Timeframe | MRR (₹) | MRR (USD) | Customers | Key Sources | Probability | Status Badge |
|:------|:------|:----------|:--------|:----------|:----------|:------------|:------------|:-------------|
| **P0** | Pre-Launch (now → 3 months) | 0 | ₹0–₹0 | $0–$0 | 0 | none — building | 100% | <img src="https://img.shields.io/badge/P0-ACTIVE-green?style=flat-square" alt="Active"> |
| **P1** | Early Beta (3-6 months) | 0-5 (friends / open-source sponsors) | ₹0–₹5,000 | $0–$60 | 0-5 (friends / open-source sponsors) | GitHub Sponsors (₹500-2000/month from 2-5 sponsors), Ko-fi / Buy Me a Coffee one-time (₹200-500/transaction), Patreon dev log tier (₹100-500/month/patron) | 60% | <img src="https://img.shields.io/badge/P1-BETA-yellow?style=flat-square" alt="Beta"> |
| **P2** | First Paying Customers (6-12 months) | 5-25 | ₹5,000–₹30,000 | $60–$360 | 5-25 | Managed UOM setup service: ₹2000-5000 one-time per customer, Monthly infra SaaS subscription: ₹500-1500/month/customer, Consulting: ₹500-1000/hour for custom integrations, GitHub Sponsors growing: ₹3000-8000/month, omni-saas factory beta access: ₹1000-3000/month/seat | 35% | <img src="https://img.shields.io/badge/P2-PLANNED-lightgrey?style=flat-square" alt="Planned"> |
| **P3** | Growth Phase (12-24 months) | 25-150 | ₹30,000–₹150,000 | $360–$1800 | 25-150 | SaaS subscriptions (core product): ₹15000-80000/month, Swarm factory jobs (per-project): ₹5000-30000/project, API reseller margin on model calls: ₹2000-10000/month, Consulting / custom mesh setup: ₹10000-30000/month, Training / docs access tier: ₹1000-5000/month | 15% | <img src="https://img.shields.io/badge/P3-PLANNED-lightgrey?style=flat-square" alt="Planned"> |
| **P4** | Scale Phase (24-36 months) | 150-500 | ₹150,000–₹500,000 | $1800–$6000 | 150-500 | Multi-seat enterprise subscriptions, White-label UOM mesh for other solo devs / micro-agencies, Swarm output as a service (research packs, build packs), Revenue share on Stripe products built by swarms | 5% | <img src="https://img.shields.io/badge/P4-PLANNED-lightgrey?style=flat-square" alt="Planned"> |

### 2.2 Three Billing Models

| Model | Mechanism | Example | Target Margin |
|:------|:----------|:--------|:--------------|
| **Credit-Based Utility** | Users purchase credit packages via Dodo Payments; execution consumes credits [ESTIMATE: based on Dodo standard micro-billing] | 5 credits per local code run | 80-90% |
| **Outcome-Based Performance** | Flat rate per completed and verified task | ₹40 ($0.50) per verified lead | 70-85% |
| **Sovereign MCP Server** | Per-query billing for local database or compute exposed as secure MCP endpoints [ESTIMATE: pricing to fit free API margins] | ₹0.80–₹8.00 ($0.01-0.10) per query | 60-80% |

**Singapore Advantage:** S-Pass holder status enables access to higher ticket SGD 100-500/hr consulting contracts [ESTIMATE: Singapore tech consulting market rates] unavailable in pure-India market, allowing cross-border arbitrage.

---

## 3. Revenue Timeline — Three Scenarios

| Scenario | Timeline | Total Investment (₹) | Monthly Rev at Target (₹) | Monthly API Cost (₹) | Net Monthly (₹) | Annual Net (₹) | Breakeven | Probability | Note |
|:---------|:---------|:---------------------|:--------------------------|:---------------------|:----------------|:---------------|:----------|:------------|:-----|
| Conservative (most likely) | 12 mo | ₹5,000 | ₹10,000 | ₹2,000 | ₹8,000 | **₹96,000** | 1 mo | 60% | Only achievable if first 5 paying customers reached at month 6 |
| Realistic (median path) | 18 mo | ₹25,000 | ₹35,000 | ₹8,000 | ₹27,000 | **₹324,000** | 6 mo | 35% | Requires consistent shipping + content presence (Shadow Narratives cross-promo helps) |
| Optimistic (top 10% scenario) | 24 mo | ₹100,000 | ₹200,000 | ₹40,000 | ₹160,000 | **₹1,920,000** | 3 mo | 5% | Requires enterprise contract or viral product launch |

**Warning:** Solo non-developer SaaS median MRR at 12 months is under $500/month globally. INR pricing gives competitive edge in Indian market. Singapore re-entry may unlock higher-ticket consulting contracts.

---

## 4. API Cost Analysis per Tier

Model pricing is analyzed per operational tier based on current API costs [SOURCE: OpenRouter model pricing & Anthropic/Google API pricing 2026]:

| Tier | Models | Monthly Cost (USD) | Tokens/Month | Suitable For | Operational Risk | Source / Basis |
|:-----|:-------|:-------------------|:-------------|:-------------|:-----------------|:---------------|
| **Free Tier (current default)** | deepseek-v4-flash-free, north-mini-code-free, big-pickle via openrouter | $0 | ~500K-2M (rate limited) | solo dev, prototyping, demo, early beta | Rate limits hit under load. No SLA. Model availability varies. | ESTIMATE: OpenRouter free tier observed limits |
| **Startup Tier (first paying customers)** | claude-haiku-4-5, deepseek-v3, gemini-flash | $20–$150 | ~5M-20M | 1-50 paying customers, basic SaaS workloads | Cost spikes on long QA loops. Need hard budget caps. | ESTIMATE: Anthropic/Google pricing pages 2026 |
| **Growth Tier (scaling)** | claude-sonnet-4-6, gpt-4o-mini mix, deepseek-v3 | $300–$1500 | ~50M-200M | 50-500 customers, full swarm pipelines | Tight margin if price-to-cost ratio not calibrated. | ESTIMATE |
| **Enterprise Tier** | claude-opus-4-8, GPT-4o, custom fine-tunes | $2000–$10000 | 500M+ | enterprise contracts, SLA-backed pipelines | Requires significant capital before revenue at this scale. | ESTIMATE |

**Prompt Caching Advantage:** Up to 98% input cost reduction on prompt cache hits [SOURCE: Google/Anthropic pricing docs]. Total session cost formula:
```text
Cost_session = Σ(Input_miss · Price_miss + Input_hit · Price_hit + Output · Price_out) + Runtime_overhead
```
Recommended local development budget cap is set to $5/month [ESTIMATE: local developer budget limit].

---

## 5. Hardware Investment Phases

Phased hardware upgrades to resolve local compute bottlenecks and prepare for scaling:

### 5.1 Phase 1: Immediate Critical Fix (Now — 1 month) — Total Budget: ₹3,000 [ESTIMATE]

| Item | Cost (₹) | Priority | Reason | Target Source |
|:-----|:---------|:---------|:-------|:--------------|
| SATA Data + Power cable replacement | ₹200 | **CRITICAL** | Eliminates I/O failures that corrupt QEMU disk images | Amazon India / local electronics market |
| 16GB DDR3L SO-DIMM RAM upgrade (HP Pavilion compatible) | ₹1,500 | **HIGH** | Doubles QEMU capacity. Enables 2x guests + Zen Loop + verifier simultaneously | OLX / Amazon India / local PC shop |
| 120GB SSD (SATA) as boot drive | ₹1,300 | **HIGH** | 10x I/O improvement. QEMU disk images on SSD = dramatically faster guest boot | Amazon India — brands: WD Green, Kingston A400 |

**Expected Uplift:** 50-100% QEMU performance improvement. Eliminates data corruption risk.

### 5.2 Phase 2: Beta Launch (Months 3-9 (first revenue reinvestment)) — Total Budget: ₹20,000 [ESTIMATE]

| Item | Cost (₹) | Priority | Reason | Target Source |
|:-----|:---------|:---------|:-------|:--------------|
| Raspberry Pi 5 (8GB) — always-on worker node | ₹8,000 | **HIGH** | Replaces phones as reliable background worker. ARM64 native. 24/7 uptime. No battery drain. | Robu.in / CanaKit India |
| 4TB External HDD (USB 3.0) for artifact + bundle storage | ₹6,500 | **MEDIUM** | Git bundle archive, QCOW2 image backups, research cache persistence | Amazon India — Seagate / WD Portable |
| Gigabit Ethernet switch (5-port) | ₹1,500 | **MEDIUM** | Wired LAN eliminates WiFi instability for Phone2 hotspot setup | Amazon India — TP-Link TL-SG105 |
| Managed VPS baseline (DigitalOcean/Hetzner $5/month) | ₹400/mo | **MEDIUM** | Offload Git remote, webhook receiver, and light API relay away from phones | Hetzner (cheaper) — CX11 €3.99/month = ~₹360/month |

**Expected Uplift:** Stable 24/7 mesh without phone battery dependency. Customer-grade uptime.

### 5.3 Phase 3: First Revenue (Months 9-18 (reinvest from revenue)) — Total Budget: ₹80,000 [ESTIMATE]

| Item | Cost (₹) | Priority | Reason | Target Source |
|:-----|:---------|:---------|:-------|:--------------|
| Mini PC / NUC (Intel N100, 16GB RAM, 512GB NVMe) | ₹18,000 | **HIGH** | Replace HP Pavilion as primary. N100 = 4x performance, fanless, 8W TDP. NVMe fast. | Amazon India — Beelink Mini S12 Pro or MINISFORUM UN100 |
| Upgraded VPS (4 vCPU, 8GB RAM) for swarm factory staging | ₹2,000/mo | **HIGH** | Run Swarm B (Build) and Swarm C (QA) on cloud without touching home hardware | Hetzner CPX21 ~€8/month, or Oracle Cloud Always Free (2 ARM64 VMs) |
| UPS (offline, 600VA) for laptop/mini PC | ₹4,000 | **MEDIUM** | Tamil Nadu power cuts kill QEMU disk integrity. UPS = 20-min ride-out. | Amazon India — APC BX600C-IN |

**Expected Uplift:** Production-grade mesh. First customer SLA-able. Swarm factory can run full 2-4 week QA.

### 5.4 Phase 4: Scale Phase (Months 18-36 (business reinvestment phase)) — Total Budget: ₹200,000 [ESTIMATE]

| Item | Cost (₹) | Priority | Reason | Target Source |
|:-----|:---------|:---------|:-------|:--------------|
| Dedicated server (Hetzner AX41-NVMe) — 6-core Ryzen, 64GB RAM, 2x512GB NVMe | ₹7,000/mo | **HIGH** | Host multiple customer meshes and parallel swarm pipelines concurrently | Hetzner.com — AX41-NVMe ~€38/month |
| AI accelerator card (RX 6600 or RTX 3060) if local LLM needed | ₹30,000 | **LOW** | Only needed if paid API costs exceed ₹30K/month. Keep free-tier policy as long as possible. | Amazon India / OLX used market |

**Note:** Phase 4 hardware only unlocks if Phase 3 revenue targets are hit. No speculative purchase.

---

## 6. Market Positioning & Saturation Analysis

Strategic assessment of the competitive landscape to ensure UOM steers clear of high-saturation regions:

| Segment | Saturation Level | UOM Positioning Moat |
|:--------|:-----------------|:---------------------|
| **Visual No Code Automation** | 🔴 HIGH | HIGH — Zapier, Make, n8n dominate. Red ocean. |
| **Open Source Self Host Infra** | 🟡 MEDIUM | MEDIUM — niche but growing. Clear demand for POSIX/edge. |
| **Multi Agent Swarm Cloud** | 🔴 HIGH | HIGH and growing — but mostly cloud-first. Edge angle is differentiator. |
| **Edge Ai Posix Linux** | 🟢 LOW | LOW-MEDIUM — underserved. UOM's real moat. |
| **Phone Based Ai Compute** | 🟢 LOW | VERY LOW — near-zero competition. First-mover possible. |
| **Ai Saas Factory Automation** | 🟡 MEDIUM | MEDIUM-HIGH — early movers (AutoGPT, Devika) lost steam. Agentic 2.0 rising. |
| **Free Tier Ai Orchestration** | 🟢 LOW | LOW — most tools lock free tier. UOM $0-cost policy is differentiator. |

### Competitor Pricing Comparison

| Competitor | Free Tier | Starter Plan | Pro Plan | Target User Segment | Source |
|:-----------|:----------|:-------------|:---------|:--------------------|:-------|
| **N8N** | self-hosted unlimited, cloud 5 workflows | $20/mo | $50/mo | non-technical SMB | https://n8n.io/pricing — ESTIMATE if fetch failed |
| **Dify** | OSS self-host, 200 messages/day cloud | $59/mo | $159/mo | developers + small teams | https://dify.ai/pricing — ESTIMATE |
| **Langchain Hub** | OSS + limited hub | $0/mo | $0/mo | developers | ESTIMATE |
| **Crewai Enterprise** | OSS CrewAI framework | unknown | unknown | enterprises | ESTIMATE: based on category peers |
| **Make Formerly Integromat** | 1000 ops/month | $9/mo | $29/mo | SMB non-technical | https://make.com/pricing — ESTIMATE |

---

## 7. Active Infrastructure Milestones (Evidence-Gated)

Infrastructure progression gates are strictly tied to objective verification signals:

| ID | Milestone | Gate Condition | Evidence Required | Target Timeline |
|:---|:----------|:---------------|:------------------|:----------------|
| **M1** | SATA cable replaced | Hardware fix | Boot log clean for 7 days with zero I/O resets | Week 1 |
| **M2** | 16GB RAM installed | Hardware upgrade | `free -h` shows 16GB total RAM | Week 2-4 |
| **M3** | SSD boot drive active | Installation | `lsblk` shows SSD mount point, boot time < 15s | Week 2-4 |
| **M4** | RPi 5 online + meshed | Hardware mesh | Zen Loop completes on RPi worker node | Month 3-6 |
| **M5** | Hetzner VPS as Git relay | Infra setup | Git pull/push operations execute successfully via VPS | Month 3-6 |
| **M6** | PHASE13–PHASE17 complete | Code freeze | All 5 phases GREEN in validation tests | Month 1-3 |
| **M7** | omni-saas S0 schema stable | Design review | First structured idea packet generated and checked | Month 3-6 |
| **M8** | First paying customer | Revenue gate | Invoice issued and payment cleared (₹ > 0) | Month 6-12 |

---

## 8. SaaS Factory Milestones (S0-S5)

The multi-swarm Layer 3 SaaS Factory (`omni-saas` entrypoint) progresses through five stages gated by human intervention:

| Phase | Deliverable | Status | Human Gate | Budget Cap |
|:------|:------------|:-------|:-----------|:-----------|
| **S0** | Idea packet schema + research job runner | 📋 Planned | Schema approval | $0 |
| **S1** | Build swarm on OpenCode mesh workers | 📋 Planned | Enable flag check | $0 |
| **S2** | Quarantine QA certificates + 72h soak hooks | 🔶 Partial | QA report sign-off | $0-10 |
| **S3** | Deploy adapters (Vercel/Docker/Dodo Payments) | 🔶 Hook-level | **HUMAN LAUNCH GATE** | $5-30 |
| **S4** | Stripe product/price automation | 📋 Planned | **HUMAN FINANCIAL GATE** | $0 |
| **S5** | Growth: newsletter landing, launch checklist | 📋 Planned | Content review | $0 |

### Swarm Architecture & Roles [ESTIMATE: planned architecture]
- **Swarm A (Discovery):** Scans market pains, performs keyword research, and identifies SEO gaps using DeepSeek V4 Flash.
- **Swarm B (Build):** Generates code architectures, compiles database schemas, and builds scripts using OpenCode CLI + DeepSeek Pro.
- **Swarm C (QA):** Performs persistent runtime validation, unit testing, and automated error recovery via isolated local execution.
- **Swarm D (Deploy):** Handles edge deployment configurations and hooks into Dodo Payments under human sign-off.

---

## 9. Critical Pitfalls

<details>
<summary><b>Click to expand 10 critical pitfalls and mitigations</b></summary>

| ID | Pitfall Title | Severity | Description | Mitigation Strategy |
|:---|:--------------|:---------|:------------|:--------------------|
| **P1** | The Hardware Cliff | `HIGH` | HP Pavilion 4GB RAM + failing SATA = production environment that corrupts its own disk. Every QEMU guest crash risks the QA artifacts and bundle state. The SATA cable is the #1 risk item. Fix it before any customer relies on this mesh. | SATA cable replacement (₹200) is the single highest-ROI action in the entire roadmap. |
| **P2** | Free Model Availability Is Not Guaranteed | `HIGH` | OpenRouter free tiers change without notice. deepseek-v4-flash-free, big-pickle, and other free models may impose rate limits, disappear, or degrade. The entire Zen Loop depends on $0-cost models. Any change breaks the pipeline. | Maintain a model fallback pool of 6+ free models. Implement cost-sentinel: abort if model shows any non-zero pricing. Keep paid-model code path dormant but ready. |
| **P3** | Solo Non-Developer Bottleneck | `HIGH` | UOM is AI-generated code managed by a prompt engineer. This is a strength (speed) and a risk (depth). When a bug requires deep C/kernel/assembly knowledge, or a customer asks for a feature outside LLM comfort zone, the pipeline stalls. Time-to-fix can be 3-10x longer than a developer. | Define explicit scope boundaries in customer contracts. Stick to POSIX sh / Python / Markdown layer. Outsource kernel-level work to community or defer. |
| **P4** | Phone Dependency Is Not Customer-Grade | `HIGH` | Phone2 as a hotspot + QEMU host + tunnel relay is a single point of failure. If the battery swells, the phone breaks, or Android kills background processes, the entire mesh loses its gateway. No customer SLA can be built on this. | Phase 2 hardware investment (RPi 5 + VPS) removes phone dependency from critical path. Do not sign SLA before Phase 2 hardware is online. |
| **P5** | Market Saturation in Visual AI Automation | `MEDIUM` | The no-code automation market (Zapier, Make, n8n) is saturated and well-funded. Competing directly on features is a losing bet. UOM's edge is POSIX/edge/privacy-first — but that niche is smaller. | Position UOM as the back-end mesh for builders, not a UI tool for non-technicals. Target: developers, homelab power users, solo founders who want control without cloud lock-in. |
| **P6** | Multi-Week QA Factory Is Not Free | `MEDIUM` | The multi-swarm SaaS pipeline (Swarm A-D) requires weeks of QA. On free models with rate limits, a 2-week QA soak on free tier will exhaust daily limits multiple times. The QA phase in practice will take 2-4x longer than on paid models. | Implement a budget-gated paid-model mode for Swarm C (QA) only. $10-30 for a 2-week QA run is acceptable. This is the one place where free-tier policy can be selectively relaxed. |
| **P7** | Singapore Work Permit + Income Declaration | `MEDIUM` | If Singapore S-Pass is approved and Dharani returns to employment, running a revenue-generating SaaS simultaneously may conflict with employment contract or MOM regulations on secondary income. | Review employment contract for IP and secondary income clauses before monetizing. Keep UOM as open-source with Patreon/sponsorship model (generally allowed) vs. active SaaS contracts (may need employer clearance). |
| **P8** | agentic AI Race Commoditizes the Stack | `MEDIUM` | OpenAI, Google, Anthropic, and Microsoft are all building native agent orchestration. By 2027, much of what UOM manually wires together (model routing, tool use, multi-step pipelines) may be 1-click in the major platforms. | UOM's moat is the EDGE + POSIX + zero-cost + phone mesh layer — not the LLM routing logic. The platform will commoditize; the hardware autonomy will not. Lean into the edge story. |
| **P9** | Revenue Timeline Is Longer Than Expected | `HIGH` | Solo non-developer SaaS median time to $500 MRR globally is 14-22 months. In India, INR pricing gives competitive pricing power but a smaller absolute TAM. First paying customer typically takes 6-10 months from stable MVP. | Start monetizing earlier with low-risk revenue: GitHub Sponsors, consulting time, Shadow Narratives cross-promo. Do not depend on swarm factory revenue in the first 9 months. |
| **P10** | cinai / AGI Disruption Risk | `LOW-NOW HIGH-LATER` | If cinai-level autonomous AI emerges within 18-24 months, the role of a human prompt-engineer orchestrating free models becomes redundant at the infrastructure level. The value shifts to: who owns the deployment stack and customer relationships. | Build customer lock-in through data portability and on-premise/edge value, not model quality. When AGI orchestrates itself, the edge mesh (UOM) and the customer trust layer become MORE valuable, not less. |

</details>

---

## 10. cinai / AGI Horizon

**Strategic Outlook:** Low risk currently → High disruption risk in the 18-24 month window.

UOM is architected to survive and integrate with generative media networks and Cinai Studio node pipelines [ESTIMATE: strategic horizon].
- **Hardware Sovereignty Moat:** Even if AGI achieves autonomous software engineering, the physical device mesh (Termux nodes, rootless hosts, local storage) remains human-controlled.
- **Data Residency as a Moat:** Enterprise customers have strict regulations preventing cloud AI model access. UOM's local-first secure MCP endpoints bridge private data and large models safely.
- **Arbitrage Opportunity:** Position UOM as the underlying physical/edge mesh orchestrator. When models become free, UOM's $0-cost orchestration strategy gains massive leverage.

---

## 11. Future Feature Phases (M33-M43)

| Phase | Vision / Objective | Priority | Research Basis |
|:------|:-------------------|:---------|:---------------|
| **M33** | Post-Quantum: ML-KEM-768 hybrid key exchange, ML-DSA host signatures | 🟡 MEDIUM | Crypto-agility readiness |
| **M34** | Predictive AI: CRC regression modeling, thermal telemetry, 60-min lookahead | 🟢 LOW | Needs dedicated GPU node |
| **M35** | Observability: eBPF kernel telemetry, bpftrace filters, Tetragon hooks | 🟡 MEDIUM | Linux performance analysis |
| **M36** | Edge/IoT: Nix golden images, A/B OTA, dm-verity + Secure Boot | 🟡 MEDIUM | Phase 2 hardware dependent |
| **M37** | Confidential Computing: AMD SEV-SNP, Intel TDX, ARM CCA VMs | 🟢 LOW | Enterprise isolation feature |
| **M38** | Secure MCP Server endpoints integration for major LLM client assistants | 🟠 **HIGH** | Monetization critical feature |
| **M39–M43** | Hardened Bootloader, Edge Federation, Power optimization, overlay FS | 🟡 MEDIUM | Post-revenue optimizations |

**Note:** M38 (MCP Server endpoints) remains the highest priority future feature, serving as the monetization foundation for per-query local database billing.

---

## 12. Data Sources

The data in this roadmap is grounded in these cached research files:

| Research Cache File | Source Origin | Last Fetched Date |
|:--------------------|:--------------|:-------------------|
| `market-summary.json` | GitHub Repos API, PyPI Recent Stats, OpenRouter Models List | 2026-07-21 |
| `competitor-analysis.json` | n8n.io, dify.ai, make.com pricing pages | 2026-07-21 |
| `monetization-model.json` | IndieHackers median MRR statistics, PPP India indices | 2026-07-21 |
| `hardware-roadmap.json` | Amazon India, local OLX PC parts market | 2026-07-21 |
| `reality-check.json` | Internal constraints analysis & MOM S-Pass guidelines | 2026-07-21 |
| `MASTER-RESEARCH.json` | Aggregation of all 5 research files above | 2026-07-21 |

**Monetary conversion rates used:** 1 USD ≈ 83 INR [SOURCE: XE.com 2026], 1 USD ≈ 1.34 SGD [SOURCE: MAS 2026], 1 SGD ≈ 62 INR [SOURCE: MAS 2026].

---

<p align="center">
  <i>Built on research. Grounded in data. Priced for India + Singapore.</i><br>
  <a href="README.md">← Back to README</a>
</p>
