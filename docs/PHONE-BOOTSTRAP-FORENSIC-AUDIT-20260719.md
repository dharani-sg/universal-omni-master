# Phone Bootstrap Forensic Audit — 2026-07-19

## Scope

Live installer at:
`https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh`

Branch audited: `origin/main` (commit `b68fcbb`)

## Summary

| Check | Result |
|---|---|
| `sh -n` bootstrap.sh | PASS |
| `sh -n` bootstrap-termux.sh | PASS |
| shellcheck warnings | 1 (unused variable) |
| Non-POSIX constructs | 2 (`&>` on lines 445, 447) |
| Live URL download | 754 bytes, HTTP 200, SHA-256 match |
| Phone download | Same bytes, same hash |
| `--check` creates files | YES — `.opencode.json`, `src/` directory |
| Argument forwarding | BROKEN — child does not receive "$@" |

## Defects Found

### BLOCKER

| # | Issue | File:Line | Risk on new phone |
|---|---|---|---|
| B1 | `--check` creates files under HOME (opencode config, src/ directory) | bootstrap-termux.sh:104,386 | New phone user expects read-only; gets unexpected files |
| B2 | Argument forwarding broken — `curl|bash` does not forward "$@" | bootstrap.sh:10 | `--apply` flag silently lost; user gets check mode instead |
| B3 | No download validation before shell execution | bootstrap.sh:10 | Executes HTML error pages, truncated responses, or MITM content |

### HIGH

| # | Issue | File:Line | Risk on new phone |
|---|---|---|---|
| H1 | Hardcoded laptop IP 192.168.40.90 | bootstrap-termux.sh:362 | SSH config points to wrong host |
| H2 | Hardcoded hostname hp-pavilion.local | bootstrap-termux.sh:369 | SSH config wrong for all non-hp-pavilion users |
| H3 | Hardcoded user "alpine" | bootstrap-termux.sh:346,355,365,371 | SSH fails with wrong username |
| H4 | SSH config overwrite replaces entire file | bootstrap-termux.sh:333-373 | Destroys existing SSH config |
| H5 | StrictHostKeyChecking=no on all hosts | bootstrap-termux.sh:350,359 | Weakens SSH security |
| H6 | No checksum/signature validation | bootstrap.sh | Executes unverified content |
| H7 | curl|bash pattern executes before validation | bootstrap.sh:10 | No content-type, size, or syntax check |

### MEDIUM

| # | Issue | File:Line | Risk |
|---|---|---|---|
| M1 | `&>` non-POSIX in boot script | bootstrap-termux.sh:445,447 | Boot fails on POSIX sh |
| M2 | `$0` shows bash path instead of script name | bootstrap-termux.sh:518 | User gets confusing install command |
| M3 | Mutable branch ref (main) | bootstrap.sh:6 | No reproducibility |
| M4 | No Termux:Boot plugin verification | bootstrap-termux.sh:418-453 | Boot script installed but never runs |
| M5 | No rollback mechanism | — | Partial install leaves broken state |
| M6 | No idempotency for SSH blocks | bootstrap-termux.sh:342-373 | Duplicate config on re-run |
| M7 | No `--verify` standalone mode | — | Cannot validate install separately |
| M8 | No `--test-root` support | — | Cannot test without affecting real system |
| M9 | No `--ref` for pinned version | — | Cannot install specific version |
| M10 | Repo directory created in check mode | bootstrap-termux.sh:386 | `mkdir -p` in check path |

### LOW

| # | Issue | File:Line |
|---|---|---|
| L1 | `storage_warned` unused variable | bootstrap-termux.sh:96 |
| L2 | No installer lock | — |
| L3 | No interrupt handling traps | — |
| L4 | SSH key detection reads real HOME in check mode | bootstrap-termux.sh:290 |

## Baseline Test Results

Tested live installer on real phone with disposable HOME:

```
PRE: 0 files under BASELINE_ROOT
Run: sh bootstrap.sh --check
POST: 2 files created (violation of read-only contract)
  - .opencode.json (71 bytes)
  - src/ directory
$0 in child: /data/data/com.termux/files/usr/bin/bash (wrong)
Mode reported: check (correct, but files were created)
```

## Verdict

The current live installer has 3 blockers, 7 high-severity issues, and
10 medium/low issues. It must not be used as-is for fresh phone installs.
