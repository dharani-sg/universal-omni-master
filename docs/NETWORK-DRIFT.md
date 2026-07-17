# Network Drift and Switching

Reference: HEAD f34b633, tag v0.31.0-2026-07-17. Date: 2026-07-17.

## Problem

The laptop connects to the internet either through the phone's wireless hotspot or
through another WiFi source. The laptop's own IP and the phone's LAN IP shift
constantly. Termux on Android can change the sshd port it listens on.

## How the System Handles Drift

### Port Guardian Sentinel

`bin/uom-port-guardian.sh` is a background sentinel that continuously watches for
both kinds of drift and re-points everything automatically:

- **Host/port discovery** using `tools/uom-port-watch.sh` primitives:
  stored hint, known IPs, subnet scan for phone sshd port
- **Drift reaction** (every ~20s loop):
  - rewrites `~/.ssh/config` `uom-phone-rev` / `uom-phone-lan` to live host:port
    (idempotent, atomic, no duplicates)
  - publishes `.uom-agent/phone.host` and `.uom-agent/laptop.host` hints
  - touches `.uom-agent/runtime/portguard.drift` to signal the hybrid orchestrator
  - on phone role: restarts `uom-reverse-ssh.sh` against the laptop's current target
  - on laptop role: keeps config + hints correct, phone-side guardian owns the tunnel

### Discovery Methods (in priority order)

1. Reverse SSH tunnel (`127.0.0.1:31415` — always works if tunnel is up)
2. mDNS (`mi8.local` / `hp-pavilion.local`)
3. Last-known IP from `.uom-agent/*.ip`
4. SSH config aliases
5. Subnet scan (nmap port 8022/22)
6. Gateway range scan (.100-.110)

### Network Context Detection

`tools/uom-net-detect.sh` provides pattern-based detection:
- `HOTSPOT` — laptop tethered through phone hotspot (detected via gateway)
- `LAN` — both devices on same network segment
- `EXTERNAL` — laptop on different network, tunnel is the only path
- `OFFLINE` — no connectivity

## Next Milestone: M31 Network Switching Stress Test

M31 will validate hotspot-to-LAN transitions, verifying that the guardian keeps the
tunnel and SSH config correct with zero manual intervention. See README for details.

### Stale Port 18022 References

Port 18022 was used in early M30 development. It has been superseded by port 31415.
The verifier (`scripts/uom-verifier.sh`) and dry-run suite (`scripts/uom-dryrun.sh`)
both check for stale 18022 references in production code.

## Tunnel Configuration Constants

| Constant | Value | Location |
|----------|-------|----------|
| Tunnel port | 31415 | bin/uom-reverse-ssh.sh, tools/uom-port-watch.sh |
| Tunnel bind | 127.0.0.1 | All tunnel scripts |
| Phone sshd port | 8022 | install/bootstrap-termux.sh |
| Old tunnel port | 18022 | Deprecated — scripts/uom-final-fix.sh (historical) |
