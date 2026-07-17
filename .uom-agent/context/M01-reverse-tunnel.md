## Context: M01 — Reverse SSH Tunnel Reliability

The UOM dual-agent system needs a reliable reverse SSH tunnel from phone to laptop.
This enables the laptop to reach the phone even when the phone is behind NAT or on a
different subnet.

Current state:
- Phone runs Termux sshd on port 8022
- Laptop can SSH to phone via LAN (currently at 192.168.40.207:8022)
- Reverse tunnel (port 18022 on laptop → phone:8022) is NOT yet established
- Script at ~/bin/uom-reverse-ssh.sh on phone handles reconnection

Task: Review and fix the reverse tunnel script on the phone to:
1. Auto-discover laptop IP (via mDNS, last-known, or gateway scan)
2. Establish ssh -N -R 18022:localhost:8022 tunnel
3. Auto-reconnect on failure with exponential backoff
4. Log to ~/.uom-reverse-ssh.log
5. Run as a daemon via nohup or tmux
