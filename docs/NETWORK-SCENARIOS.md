# Network Scenarios Reference

Date: 2026-07-18. HEAD: 97e4c76.

## Scenario Matrix

| # | Scenario | Detection | Response | Recovery | Status |
|---|----------|-----------|----------|----------|--------|
| 1 | Laptop on phone hotspot | `uom-net-detect.sh` hotspot pattern | Phone IS gateway, no tunnel needed | N/A | ✅ |
| 2 | Both on same LAN (192.168.x.x) | `uom-net-detect.sh` lan mode | Direct SSH + mDNS discovery | Port guardian rewrites SSH config | ✅ |
| 3 | Laptop on different WiFi | `uom-net-detect.sh` external mode | Reverse tunnel only path | Port guardian detects change | ✅ |
| 4 | Phone IP changes | `uom-watchdog.sh` IP drift check | Tunnel auto-restart, SSH wrapper re-discovers | `uom-ip-discover.sh` 5-method chain | ✅ |
| 5 | Laptop IP changes | `uom-port-guardian.sh` fingerprint change | SSH config rewrite + hint update | 20s polling loop | ✅ |
| 6 | Phone goes offline | `uom-watchdog.sh` 3-check failure | Takeover to `phone-solo` after threshold | Wake-lock keeps phone alive | ✅ |
| 7 | Laptop goes offline | `uom-watchdog.sh` heartbeat stale | Wait for laptop return | `dual-pending` on return | ✅ |
| 8 | Both go offline | Watchdog can't detect (correct) | No action (safe default) | Reconnect when back | ✅ |
| 9 | Phone reboots | Tunnel drops, reverse-ssh retries | Reverse-ssh reconnect loop (10s) | Port guardian detects on next poll | ✅ |
| 10 | Laptop reboots | Watchdog detects stale heartbeat | Phone waits, no premature takeover | Port guardian re-discovers | ✅ |

## How It Works

### Network Mode Detection

`tools/uom-net-detect.sh` detects the current mode:

```
NET_MODE=hotspot   → Laptop tethered to phone (phone is gateway)
NET_MODE=lan       → Both devices on same network
NET_MODE=external  → Laptop on different network (tunnel only)
NET_MODE=offline   → No connectivity
```

### IP Discovery Chain

`tools/uom-ip-discover.sh` finds the other device:

1. **Reverse tunnel** (`127.0.0.1:31415`) — always works if tunnel is up
2. **mDNS** (`mi8.local` / `hp-pavilion.local`) — works on same LAN
3. **Last-known IP** from `.uom-agent/*.ip` — cached, verified
4. **SSH config aliases** — `uom-phone-rev`, `uom-phone-lan`, `uom-phone-mdns`
5. **Subnet scan** — brute force but reliable (last resort)

### Port Guardian

`orchestrators/uom-port-guardian.sh` runs on the laptop:

- 20s polling loop with network fingerprint
- Detects topology changes (hotspot ↔ LAN ↔ external)
- Rewrites SSH config (idempotent UOM-MANAGED block)
- Signals drift to reconcile script
- Updates `.uom-agent/*.host` hints

### Phone Watchdog

`orchestrators/uom-watchdog.sh` runs on the phone:

- 30s polling loop checking laptop reachability
- Three checks: heartbeat, tunnel, direct IP/mDNS
- Threshold-based takeover to `phone-solo` mode
- IP drift detection → tunnel auto-restart
- Hotspot mode detection (phone is gateway)
- Wake-lock on solo mode entry
- Phone announce (writes `phone.ip` to state)

### SSH Wrapper

`bin/uom-ssh-phone.sh` is the single entry point for laptop → phone SSH:

- Phone-announce file check (freshest IP)
- Hotspot gateway detection (phone IS gateway)
- Cached IP → reverse tunnel → mDNS → subnet scan
- Identity verification (SSH auth + host key + uom-vm dir)
- Caches to `~/.config/uom/last-phone-ip.txt`

### Reverse Tunnel

`bin/uom-reverse-ssh.sh` creates phone → laptop tunnel:

- Phone-initiated: `laptop:31415 → phone:8022`
- autossh or manual retry loop
- Pre-flight laptop reachability check
- Singleton enforcement (mkdir lock + PID validation)
- ServerAliveInterval=30, CountMax=3

## Constants

| Constant | Value | Used By |
|----------|-------|---------|
| Tunnel port | 31415 | All tunnel scripts |
| Phone SSH port | 8022 | All phone connections |
| Watchdog interval | 30s | Phone watchdog |
| Guardian interval | 20s | Port guardian |
| Fail threshold | 6 cycles | Takeover trigger |
| Stale heartbeat | 300s | Watchdog |
| Rate limit default | 60s | Model rotation |

## Model Rotation

`tools/uom-model-rotate.sh` manages free model selection:

- Pool: `deepseek-v4-flash-free`, `nemotron-3-ultra-free`, `north-mini-code-free`, `big-pickle`
- Probes models, caches working one
- Handles rate limits (429) with Retry-After headers
- Online-only operation
- History tracking (last 50 entries)
