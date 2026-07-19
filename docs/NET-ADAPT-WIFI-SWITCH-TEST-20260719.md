# WiFi Switch Dry-Run — 2026-07-19

## Route Summary (Laptop)
- Old subnet: 192.168.40.0/24 (previous WiFi)
- New subnet: 10.21.250.0/24 (phone2 hotspot)
- Laptop IP: 10.21.250.90/24 via wlan0
- Gateway: 10.21.250.151 (phone2)

## Phone Reachability

| Node | IP | User | Model | SDK | Free Disk | Reachable |
|------|----|------|-------|-----|-----------|-----------|
| Phone1 (main) | 10.21.250.76 | u0_a608 | MI 8 | 35 | 36G | YES |
| Phone2 (mom) | 10.21.250.151 | u0_a217 | 23106RN0DA | 35 | 47G | YES |

## Tunnel Ports

| Port | Status | Notes |
|------|--------|-------|
| 2222 | NOT LISTENING on laptop | Phone1 QEMU forwards 2222->22 guest, but no reverse tunnel from laptop |
| 2223 | NOT LISTENING on laptop | No reverse tunnel established |
| 8022 | Direct SSH on both phones | Used for direct phone access on current subnet |

## Wrapper (bin/uom-ssh-phone.sh)
- Works for Phone1 (discovered at 10.21.250.76)
- Uses key ~/.ssh/id_ed25519_phone
- User u0_a608 (confirmed)
- Verify output: "Identity OK at 10.21.250.76"

## Network Topology
- Phone2 is the WiFi hotspot/gateway (10.21.250.151)
- Laptop and Phone1 connect through Phone2's hotspot
- No reverse SSH tunnels needed on same subnet (direct SSH works)

## Cached IPs (Stale — from old 192.168.40.x network)
- Old laptop.ip: 192.168.40.90
- Old phone.ip: 192.168.40.207
- Both updated on discovery

## Verdict: PASS
- Laptop route coherent
- Both phones reachable via direct SSH
- Wrapper works for Phone1
- QEMU VM running correctly on Phone1 (qemu-system-aarch64, no x86_64)
