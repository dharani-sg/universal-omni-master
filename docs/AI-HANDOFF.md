# Universal Omni-Master — Durable AI Handoff

## Repository identity

- Project: Universal Omni-Master
- Root: `~/src/universal-omni-master`
- Core language: POSIX `#!/bin/sh`
- TUI language: Fish 4.x only
- Reference host: Alpine Linux, musl, OpenRC
- Secondary host: Void Linux, glibc, runit
- Hardware: HP Pavilion 15-n010tx
- SATA CRC baseline: 5360; stable baseline is not a new failure
- Muxless AMD dGPU remains available through policy/driver override

Do not confuse this project with the older `omni-master` dual-boot
administration suite.

## Immutable engineering rules

1. Core code must remain POSIX and BusyBox-ash compatible.
2. Never use `eval`.
3. Never use `set --` to parse unrelated strings while CLI arguments are live.
4. Any mutation under `OMNI_SYSROOT` must return `126`.
5. Never claim a command ran without terminal output proving it.
6. Never push when any gate is failing.
7. Never rewrite or move an existing Git tag.
8. Restore must use staged RW clone plus boot entry.
9. Restore must never reboot automatically.
10. Alpine owns the primary GRUB; never run `grub-install` from Void.
11. Verify OS and `pwd` before every command block.
12. Commit messages containing `$`, `${}`, backticks, or `$(...)` must use
    `git commit -F file`, not `git commit -m "..."`.

## Verified milestone history

| Milestone | Capability |
|---|---|
| M1 | Hardware/software detection |
| M2 | Five-init service abstraction |
| M3 | Bootloader abstraction |
| M4 | GPU policy engine |
| M5 | SMART/NVMe/Btrfs telemetry |
| M6 | Structured audit and diagnostics |
| M7 | Universal deploy/bootstrap |
| M8 | Self-healing daemon |
| M9 | Healer init integration |
| M10 | Snapshot lifecycle |
| M11 | Staged rollback and boot entries |
| M12 | Deterministic Fish TUI |
| M13-A | POSIX monolith bundler |

## Tag notes

- `v0.13.0-a1` and `v0.13.0-a3` were alpha attempts with known monolith failures.
- `v0.13.0` was accidentally created before the final fixed commit due to a
  failed shell-expanded commit message.
- Do not rewrite those tags.
- `v0.13.1` supersedes them as the fixed M13-A release.

## Critical bug history

- BusyBox `dmesg` has no `-w`; use poll-diff mode.
- BusyBox `sed` does not process replacement newline like GNU sed.
- `set --` overwrote `omni-tui` arguments and caused every non-TTY route to exit 4.
- `boot_entry_list` was wrong; the implemented function is `snap_boot_entry_list`.
- Static shell flattening is dangerous because interface modules execute backend
  detection and dynamic source selection at source time.
- Current M13-A solution wraps library loading and validates dispatch through tests.
- Long terminal heredocs can be interrupted. Always run syntax and gate checks.

## Required gates

```sh
./scripts/test-m13-monolith.sh
./scripts/compat-check.sh
./scripts/test-boot.sh
./scripts/test-gpu.sh
./scripts/test-storage.sh
./scripts/test-audit.sh
./scripts/test-deploy.sh
./scripts/test-healer.sh
./scripts/test-m9-healer-install.sh
./scripts/test-m10-snapshot.sh
./scripts/test-m11-rollback.sh
fish --no-config scripts/test-m12-tui.fish
```

## Known historical artifact (accepted, not eradicated)

- Commit `4889ba2` accidentally committed a 5,136-line generated build
  artifact named `_STAGE`; removed in `5a39459` (v0.13.2).
- The blob remains reachable in history. DECISION: retained, because it
  contains zero secrets (generated from public src/), is size-trivial,
  and eradication via filter-repo would force-move tags v0.13.2/v0.13.3,
  violating the never-rewrite-tags rule.
- `.gitignore` now blocks `_STAGE` and monolith artifacts permanently.
- Verification lesson: `git ls-files <path>` exits 0 even with no match;
  tracking checks MUST use `git ls-files --error-unmatch <path>`.

## Tag recovery exception (v0.13.4, 2026-07-12)

- v0.13.4 was accidentally minted and pushed on commit da8ca59 (a docs
  commit) while src/plugin/engine.sh was missing due to a wrong-directory
  + truncated heredoc. Deleted locally and remotely within minutes of
  creation and re-minted on the real M13-C commit. This is the ONLY
  sanctioned never-rewrite-tags exception: same-session, minutes-old,
  feature-absent, zero consumers. Anything older is superseded forward.
- Lesson: verify pwd BEFORE every heredoc; verify tail -3 + wc -l AFTER.

## M21 Addition (v0.21.0)
- bin/omni-manager: audit-sync, list-clis, list-tools, add/remove-tool, snapshot
- src/manager/control.sh: repo health + mutation-guarded registry ops
- manager_snapshot_meta stdout: path only; info message → stderr (snapshot pollution fix)
- Used POSIX sed instead of grep -oP (BusyBox has no PCRE)
- For-glob inventory instead of find+xargs for portability

## Bug History Addition #13
- mkfifo + & background jobs: named pipes and background processes can leak
  on Ctrl+C in livefeed.sh. Mitigation: always include a direct-exec fallback.
  FD3 redirection is the production-grade fix deferred to M22+.
