# Universal Omni-Master — AI Handoff / Fail-Safe Context

## System
- Reference host: HP Pavilion 15-n010tx; Alpine Linux (musl, OpenRC, apk, doas),
  dual-boot Void (glibc, runit, xbps). Interactive shell: fish 4.x. WM: niri (Wayland).
- Known hardware quirks: degraded SATA cable (stable UDMA_CRC baseline 5360 — NOT a
  failure), muxless AMD HAINAN dGPU, AC-only power.

## Immutable constraints
- Core = POSIX `#!/bin/sh`, BusyBox-ash-safe, ZERO bashisms. No GNU-only flags.
- Fish is ONLY for the TUI (src/tui/*.fish), run via `fish --no-config`.
- No `eval` anywhere. Build commands as Fish lists / positional args.
- Mutation guard: any state-changing op MUST return exit 126 when OMNI_SYSROOT is set.
- Btrfs: non-Btrfs = graceful skip (return 0), never hard-fail hooks.
- Root subvol convention is **@root**; snapshots container is **@snapshots**.
  Do NOT change to @ — M7 bootloader pins rootflags=subvol=@root.
- Restore MUST NOT use `btrfs subvolume set-default` (cmdline subvol= overrides it).
  Use staged RW clone + boot entry instead.

## Milestones
| M | Feature | Tag |
|---|---|---|
| M1-M6 | detect/init/boot/gpu/storage/audit | v0.1.0–v0.6.0 |
| M7 | omni-deploy installer | v0.7.2 |
| M8 | omni-healer daemon | v0.8.1 |
| M9 | healer init service integration | v0.9.0 |
| M10-A | omni-snapshot lifecycle | v0.10.0 |
| M11 | atomic rollback + boot-to-snapshot | v0.11.0/v0.11.1 |
| M12 | Fish TUI (omni-tui) | v0.12.0 (in progress) |
| M13 | plugins + remote nodes | planned |

## Gate commands
- Syntax: `sh -n <file>` (POSIX), `fish --no-config --no-execute <file>` (Fish)
- Suites: scripts/test-*.sh and scripts/compat-check.sh
- M12: `fish --no-config scripts/test-m12-tui.fish`
- M11 audit: `./scripts/audit-m11.sh`

## Hard rules
- NEVER push if any suite fails.
- NEVER rewrite or move existing tags.
- NEVER use eval.
- NEVER claim a command ran without showing terminal output.
- Restore/apply require typed target + literal APPLY/RESTORE (double confirmation).

## Current blockers (update each session)
- M12 launcher TTY-bypass fixed (arg-scan _need_tty=0 for plain/read-only routes).
- M11.1: restore rewritten (no set-default), boot-once dispatch added,
  deploy payload now ships boot_entry.sh + restore.sh.
