# README Conflict Analysis — R1.1

Date: 2026-07-18. Auditor: opencode. Branch: refactor/structure-audit-2026-07-17.

## Purpose

Audit `README.md` (730 lines) against actual repo state to identify every stale, incorrect, or misleading claim. This drives the R1.2 README rewrite.

---

## Conflict Summary

| # | Severity | README Claim | Actual State | Lines |
|---|----------|-------------|-------------|-------|
| 1 | **CRITICAL** | Version badge: v0.32.0 | No v0.32.0 tag exists. HEAD at 44443c5 (Phase 12). Last tag: `uom-phone-qemu-phase9-20260718` on ebe18b6. ROADMAP says v0.30.0. | 4 |
| 2 | **CRITICAL** | "Sealed: Foundation through Cloud (M1–M30.5)" + "v0.32.0" in roadmap | Phase 9-12 (network auto-switch, model rotation, port guardian restored, documentation) are fully complete and pushed. Not reflected anywhere. | 382-396 |
| 3 | **CRITICAL** | "Remaining TODO (Phase 10–13): Pending" | Phase 10 (model rotation), Phase 11 (integration verification), Phase 12 (documentation) are DONE. Phase 13 (revoke Termux root) is the only remaining. | 677-684 |
| 4 | **CRITICAL** | Milestone Status: "M31: Pending (gate for M33-M37)" | M31 is not the active queue. queue.json has M33-M37 (Zen Loop pipeline tests), all pending. README's M31 description doesn't match queue.json. | 709-716 |
| 5 | **HIGH** | M33-M37 described as "Zen Loop pipeline tests" (README) | queue.json describes them as: M33=SSH remote LLM verify, M34=phone generator loop, M35=bidirectional sync, M36=verifier feedback, M37=e2e zen loop. More specific than README. | 709-716 vs queue.json |
| 6 | **HIGH** | "Zen Loop Cloud Pipeline (v0.32.0)" section header | Phase 9-12 added network auto-switch, model rotation (uom-model-rotate.sh), port guardian restoration. None mentioned. | 104-190 |
| 7 | **HIGH** | Dynamic model pool: 6 models listed | README lists: deepseek-v4-flash-free, big-pickle, mimo-v2.5-free, nemotron-3-ultra-free, glm-4.7-free, north-mini-code-free. uom-model-rotate.sh pool: deepseek-v4-flash-free, nemotron-3-ultra-free, north-mini-code-free, big-pickle. Only 4 models. | 120-128 |
| 8 | **HIGH** | Known Issues: "Port 18022 retired" + "Dynamic port range: 31400-31499" | Port guardian uses fixed 31415 (NETWORK-SCENARIOS.md line 89). DRYRUN still has false-positive FAIL from stale 18022 ref. Port range claim contradicts actual fixed port. | 590-591 |
| 9 | **HIGH** | "Phone-Only QEMU Architecture (Phase 9.5)" | Phase 9.5 is an old label. Through Phase 12, the architecture has been extended. Section heading is misleading. | 595 |
| 10 | **MEDIUM** | File structure lists `orchestrators/uom-hybrid.sh` | Audit report (section 2F) says this is a DUPLICATE, should be deleted. README still lists it. | 258 |
| 11 | **MEDIUM** | File structure lists `UOM-DUAL-AGENT/` | Audit report (section 7.5) says these are OBSOLETE, should be pruned. README still lists them. | 306 |
| 12 | **MEDIUM** | "Safe Bootstrap Download" points to `refactor/structure-audit-2026-07-17/scripts/uom-phone-bootstrap.sh` | URL is branch-specific, will break on branch rename. Should point to `main` or a tag. | 688-701 |
| 13 | **MEDIUM** | "Release Links": pinned tag `uom-phone-qemu-phase9-20260718` | This tag is on ebe18b6 (before refactor). After R6, a new tag will be created. Stale. | 705-707 |
| 14 | **MEDIUM** | "Validated Environments": Alpine 3.24 | Actual: Alpine 3.21 (guest), Alpine (laptop). Version number is wrong. | 530-537 |
| 15 | **LOW** | "62 POSIX Shell Library Modules" in architecture diagram | Unclear count. Actual module count in src/ not verified. | 208-210 |
| 16 | **LOW** | "300+ Assertions" in test badge | Not verified against actual test count. | 3 |
| 17 | **LOW** | Roadmap M32-M43 descriptions | These are future/horizon items, not necessarily wrong, but M33-M37 conflict with queue.json descriptions. | 398-413 |
| 18 | **LOW** | "Bulletproof State Recovery" claims | No evidence these were tested in Phase 9-12. Conceptually correct but unverified. | 518-524 |

---

## Detailed Conflict Analysis

### C1: Version Number Chaos

README badge says v0.32.0 (line 4). Architecture diagram says v0.32.0 (line 199). Zen Loop section says v0.32.0 (line 104). But:
- ROADMAP.md says HEAD is v0.30.0 (line 4)
- No git tag v0.32.0 exists
- Last tag is `uom-phone-qemu-phase9-20260718` on commit ebe18b6
- After R6, a new tag will be `uom-stable-phase12-YYYYMMDD`

**Verdict:** README v0.32.0 was aspirational, never sealed. The actual version is best described as "Phase 12" or "v0.33.0" (post Phase 12).

### C2: Phase 9-12 Work Invisible in README

Phase 9 (Network Auto-Switch): port guardian restored, phone watchdog extended, reverse tunnel hardened, SSH wrapper enhanced. None mentioned.

Phase 10 (Free Model Rotation): `tools/uom-model-rotate.sh` created with 5 subcommands, Retry-After handling, model history. Not mentioned.

Phase 11 (Integration Verification): 129/132 dryrun PASS, 3 false-positives identified. Not mentioned.

Phase 12 (Documentation): NETWORK-SCENARIOS.md, SCRIPT-CATALOG.md updated. Not mentioned.

**Verdict:** README is 4 phases behind reality.

### C3: Zen Loop Model Pool Mismatch

README lists 6 models (line 120-128):
1. deepseek-v4-flash-free
2. big-pickle
3. mimo-v2.5-free
4. nemotron-3-ultra-free
5. glm-4.7-free
6. north-mini-code-free

`uom-model-rotate.sh` pool (from NETWORK-SCENARIOS.md line 99-101):
1. deepseek-v4-flash-free
2. nemotron-3-ultra-free
3. north-mini-code-free
4. big-pickle

Only 4 models. mimo-v2.5-free and glm-4.7-free were removed (presumably non-functional or paid).

### C4: Port Range vs Fixed Port Contradiction

README claims "Dynamic port range: 31400-31499" (line 591) and "tunnel port: dynamically allocated from 31400-31499" (line 501).

But NETWORK-SCENARIOS.md (line 89) and all actual scripts use fixed port 31415. The "dynamic range" was aspirational v0.32.0 design, never implemented.

### C5: M33-M37 Description Conflict

README (lines 403-407):
- M33: "Predictive AI — CRC linear regression, thermal telemetry, 60-min failure lookahead"
- M34: "Observability — eBPF kernel telemetry, bpftrace, Tetragon TracingPolicy"
- M35: "Edge/IoT — Nix golden images, A/B OTA, dm-verity + Secure Boot"
- M36: "Confidential — AMD SEV-SNP / Intel TDX / ARM CCA detection"
- M37: "Protocol — MCP Server integration for AI assistants"

queue.json:
- M33: "ssh-remote-llm — Verify SSH-based remote LLM pipeline"
- M34: "phone-generator-loop — Verify phone generator agent"
- M35: "bidirectional-sync — Verify bidirectional sync"
- M36: "verifier-feedback-loop — Verify verifier on laptop"
- M37: "zen-loop-e2e — End-to-end zen loop test"

**Verdict:** README M33-M37 are the "Horizon" roadmap items. queue.json M33-M37 are completely different (Zen Loop pipeline verification). This is a NAMING COLLISION — same M numbers, different tasks.

---

## Recommendation

The README needs a **full rewrite**, not a patch. Key decisions for R1.2:

1. **Version number:** Use "Phase 12" or bump to v0.33.0. Remove v0.32.0 references.
2. **Phase 9-12 section:** Add a "What's New" section or update the existing feature descriptions.
3. **Model pool:** Update to 4-model pool (actual).
4. **Port:** Change "dynamic range 31400-31499" to "fixed 31415 with drift resilience".
5. **M33-M37:** Clarify that queue.json M33-M37 are pipeline verification (different from roadmap horizon M33-M37).
6. **Roadmap:** Update to reflect actual sealed phases (0-12). Move M33-M37 queue items to a separate "Pipeline Verification" section.
7. **File structure:** Remove uom-hybrid.sh (pending R4 deletion). Mark UOM-DUAL-AGENT as legacy.
8. **Bootstrap URL:** Point to main branch, not feature branch.
9. **Tag references:** Update after R6 creates new tag.

---

## STOP — USER DECISION REQUIRED

Two options for the M-phase queue (M33-M37):

### OPTION 1: Keep M-phase queue, append Phase 9-12 as new M38-M41

- queue.json keeps M33-M37 (Zen Loop pipeline verification)
- Phase 9-12 work becomes M38-M41 in queue
- Roadmap keeps M33-M43 as horizon items
- **Pro:** Preserves existing queue structure, no rename needed
- **Con:** M33-M37 naming collision between queue and roadmap persists

### OPTION 2: Replace M-phase queue with Phase-based naming

- queue.json entries renamed: M33 → PHASE13-zen-loop-ssh, etc.
- Phase 9-12 documented as completed phases (no M-number)
- Roadmap M33-M43 remains as future horizon items
- **Pro:** Eliminates naming collision, cleaner separation
- **Con:** Requires queue.json rename, context file renames

**Which option?** I will proceed with R1.2 (README rewrite) after your decision. The README rewrite itself is independent of this choice — it will reflect whichever naming scheme you pick.
