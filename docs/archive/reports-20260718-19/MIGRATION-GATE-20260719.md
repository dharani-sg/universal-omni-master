# Phone1→Phone2 Migration Gate — 2026-07-19

## Result: ALL PASS

| Gate | Status |
|------|--------|
| Phone2 SSH (8022) | PASS |
| Phone2 proot Alpine (39 pkgs) | PASS |
| Phone2 opencode 1.18.3 | PASS |
| Phone2 big-pickle model | PASS (2+2=4) |
| Phone2 QEMU VM (disk-installed, 4GB) | PASS |
| Phone2 opencode wrapper (script -qec + proot) | PASS |
| Phone1 work VM killed (PID 3949) | PASS |
| Phone1 watchdog deployed | PASS |
| Laptop opencode + big-pickle | PASS |

## Key Breakthrough
`script -qec` wraps proot-distro login to provide PTY for opencode I/O.
Without it, opencode hangs on stdin/stdout file descriptor forwarding.

## Architecture (Post-Migration)
- Phone2 (192.168.40.157:8022) = PRIMARY WORK NODE
  - ~/bin/opencode -> proot Alpine -> musl binary -> big-pickle
  - QEMU VM (Alpine 3.24, disk-installed, port 22222)
  - Node.js v26.3.1, 44GB free
- Phone1 (10.21.250.76) = WATCHDOG + FAILOVER (currently offline)
  - uom-qemu-host VM (PID 4974, permanent)
  - uom-tmux-watchdog.sh daemon
- Laptop (192.168.40.90) = PRIMARY AGENT + VERIFIER

## Phone2 Quick Reference
~/bin/opencode run 'prompt'           # Run with big-pickle
~/bin/opencode --version              # Check version
proot-distro login alpine             # Alpine shell
ssh -p 22222 root@127.0.0.1           # QEMU VM (from Phone2)
