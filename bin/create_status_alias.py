#!/usr/bin/env python3
# create_status_alias.py - Creates omni-project-status alias on phone via reverse tunnel
# Uses Python to ensure proper handling of shell commands

import subprocess
import sys
import os

# Configuration
PHONE_IP = "192.168.40.207"
PHONE_USER = "u0_a608"
PHONE_PORT = 8022

def run_command(cmd, check=True):
    """Run a shell command with timeout"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        if check and result.returncode != 0:
            print(f"Command failed: {cmd}")
            print(f"stderr: {result.stderr}")
            return None
        return result
    except subprocess.TimeoutExpired:
        print(f"Command timed out: {cmd}")
        return None
    except Exception as e:
        print(f"Error running command '{cmd}': {e}")
        return None

def check_ssh_connection():
    """Check if we can connect to phone SSH"""
    cmd = f"ssh -o ConnectTimeout=5 -o PreferredAuthentications=password -o PubkeyAuthentication=no -p {PHONE_PORT} {PHONE_USER}@{PHONE_IP} \"echo 'SSH_OK'\""
    result = run_command(cmd, check=False)
    if result and result.returncode == 0:
        print("✓ SSH connectivity OK")
        return True
    print("✗ Cannot connect to phone SSH")
    print(f"  Please ensure phone is reachable at {PHONE_IP}:{PHONE_PORT}")
    print("  Phone must have sshd running on port 8022")
    return False

def create_monitor_script():
    """Create the monitor script on phone"""
    script_content = """#!/data/data/com.termux/files/usr/bin/sh
# omni-project-status - Unified status monitor for UOM project
# Shows operational status across both laptop and phone agents

cd /src/universal-omni-master || exit

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

_status_summary() {
    _ts=$(date)
    echo "═══════ UOM ORCHESTRATOR STATUS ═══════"
    echo "TIMESTAMP: ${_ts}"
    echo "─────────────────────────────────────"

    if [ -f .uom-agent/state.json ]; then
        _state=$(cat .uom-agent/state.json)
        _mode=$(echo "${_state}" | jq -r '.hybrid_mode // "dual"' 2>/dev/null || echo "dual")
        _active_agent=$(echo "${_state}" | jq -r '.active_agent // "unknown"' 2>/dev/null || echo "unknown")
        _task_status=$(echo "${_state}" | jq -r '.task_status // "idle"' 2>/dev/null || echo "idle")
        _task_id=$(echo "${_state}" | jq -r '.current_task_id // "none"' 2>/dev/null || echo "none")
        _takeover_count=$(echo "${_state}" | jq -r '.takeover_count // 0' 2>/dev/null || echo "0")
        _queue_len=$(jq -r 'length' .uom-agent/queue.json 2>/dev/null || echo "0")

        _failed_count=$(jq -r '[.[] | select(.status == "failed")] | length' .uom-agent/queue.json 2>/dev/null || echo "0")

        echo "STATE FILE: ${GREEN}✓ OK${NC}"
        echo "  Hybrid Mode: ${_mode}"
        echo "  Active Agent: ${_active_agent}"
        echo "  Task Status: ${_task_status}"
        echo "  Current Task ID: ${_task_id}"
        echo "  Takeover Count: ${_takeover_count}"
        echo "  Pending Tasks: ${_queue_len}"
        if [ "${_failed_count}" -gt 0 ]; then
            echo "  ⚠️  FAILED TASKS: ${RED}${_failed_count}${NC}"
        fi
    else
        echo "STATE FILE: ${RED}✗ NOT FOUND${NC}"
    fi

    echo "─────────────────────────────────────"
    echo "PROCESSES:"

    if _aptest() { ps -ef | grep -v grep | grep -q \"$1\"; }; then
        case \"$1\" in
            uom-orch-laptop) echo "  LAPTOP ORCHESTRATOR: ${GREEN}✓ RUNNING${NC}" ;;
            uom-orch-phone) echo "  PHONE ORCHESTRATOR: ${GREEN}✓ RUNNING${NC}" ;;
            uom-solo-orchestrator) echo "  SOLO ORCHESTRATOR: ${GREEN}✓ RUNNING${NC}" ;;
            *) echo "  UNKNOWN PROCESS: ${YELLOW}?${NC}" ;;
        esac
    else
        case \"$1\" in
            uom-orch-laptop) echo "  LAPTOP ORCHESTRATOR: ${RED}✗ NOT RUNNING${NC}" ;;
            uom-orch-phone) echo "  PHONE ORCHESTRATOR: ${RED}✗ NOT RUNNING${NC}" ;;
            uom-solo-orchestrator) echo "  SOLO ORCHESTRATOR: ${RED}✗ NOT RUNNING${NC}" ;;
            *) echo "  UNKNOWN PROCESS: ${YELLOW}?${NC}" ;;
        esac
    fi

    echo "─────────────────────────────────────"
    echo "REVERSE TUNNEL: $(ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null && echo "${GREEN}✓ UP (port 31415)${NC}" || echo "${RED}✗ DOWN${NC}")"

    if [ -f .uom-termux-user/tunnel.pid ]; then
        _pid=$(cat .uom-termux-user/tunnel.pid 2>/dev/null)
        if ps -p \"$_pid\" >/dev/null 2>&1; then
            echo "  Tunnel Process: ${GREEN}✓ RUNNING (PID $_pid)${NC}"
        else
            echo "  Tunnel Process: ${RED}✗ NOT RUNNING${NC}"
        fi
    fi

    echo "─────────────────────────────────────"
    echo "QUEUE STATUS:"
    if [ -f .uom-agent/queue.json ]; then
        _pending=$(jq -r '[.[] | select(.status=="pending")] | length' .uom-agent/queue.json 2>/dev/null || echo "0")
        echo "  Pending Tasks: ${_pending}"
        _failed_count=$(jq -r '[.[] | select(.status == "failed")] | length' .uom-agent/queue.json 2>/dev/null || echo "0")
        if [ "${_failed_count}" -gt 0 ]; then
            echo "  Failed Tasks: ${RED}${_failed_count}${NC}"
        fi
    fi

    if [ -f .uom-termux-user/omni-orchestrator.log ]; then
        echo "─────────────────────────────────────"
        echo "LATEST LOGS:"
        echo "  Omni Orchestrator: $(tail -n 3 .uom-termux-user/omni-orchestrator.log 2>/dev/null | tail -1 || echo "none")"
    fi

    echo -e "\n"
}

case "${1:-}" in
    status|--status|--s|--print)
        _status_summary
        ;;
    full|--full|--all)
        _status_summary
        echo "═══════ DETAILED LOGS ═══════"
        if [ -f .uom-termux-user/omni-orchestrator.log ]; then
            echo "═══════ Omni Orchestrator Log (last 30 lines) ═══════"
            tail -n 30 .uom-termux-user/omni-orchestrator.log
        fi
        if [ -f .uom-termux-user/tunnel.log ]; then
            echo "═══════ Tunnel Log (last 30 lines) ═══════"
            tail -n 30 .uom-termux-user/tunnel.log
        fi
        ;;
    tunnel|--tunnel|ssh)
        if ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null; then
            echo "REVERSE TUNNEL STATUS: ${GREEN}✓ UP${NC} (connect on laptop: ssh -p 31415 127.0.0.1)"
        else
            echo "REVERSE TUNNEL STATUS: ${RED}✗ DOWN${NC}"
            echo "  Check: ps -ef | grep uom-reverse-ssh.sh"
            echo "  Start tunnel: nohup sh /uom-reverse-ssh.sh >/dev/null 2>&1 &"
        fi
        ;;
    current|--current|--c)
        if [ -f .uom-agent/state.json ]; then
            _mode=$(jq -r '.hybrid_mode // "dual"' .uom-agent/state.json 2>/dev/null)
            _active=$(jq -r '.active_agent // "unknown"' .uom-agent/state.json 2>/dev/null)
            _task=$(jq -r '.current_task_id // "none"' .uom-agent/state.json 2>/dev/null)
            echo "Current Mode: ${_mode}"
            echo "Active Agent: ${_active}"
            echo "Current Task ID: ${_task}"
        fi
        ;;
    *)
        _status_summary
        echo "─────────────────────────────────────"
        echo "Usage:")
        echo "  omni-project-status          Display current status"
        echo "  omni-project-status --full    Display status + logs"
        echo "  omni-project-status tunnel    Check reverse tunnel"
        echo "  omni-project-status current   Show current mode"
        ;;
esac

# vim: set ft=sh :"""

    cmd = f"""
cat << 'EOF' > /src/omni-project-status.sh
#!/data/data/com.termux/files/usr/bin/sh
{script_content}
EOF
chmod +x /src/omni-project-status.sh
"""
    result = run_command(cmd)
    if result and result.returncode == 0:
        print("✓ Monitor script created on phone")
        return True
    print("✗ Failed to create monitor script on phone")
    return False

def create_launcher():
    """Create the launcher script in ~/bin/"""
    cmd = """
mkdir -p ~/bin
cat << 'EOF' > ~/bin/omni-project-status
#!/data/data/com.termux/files/usr/bin/sh
cd /src/universal-omni-master
/src/omni-project-status.sh "$@"
EOF
chmod +x ~/bin/omni-project-status
"""
    result = run_command(cmd)
    if result and result.returncode == 0:
        print("✓ Launcher script created in ~/bin/")
        return True
    print("✗ Failed to create launcher script")
    return False

def add_alias():
    """Add alias to .bashrc"""
    # Read existing .bashrc or create new one
    check_cmd = "grep -q 'omni-project-status' ~/.bashrc && echo 'exists' || echo 'not_exists'"
    result = run_command(f"ssh -o ConnectTimeout=5 -p {PHONE_PORT} {PHONE_USER}@{PHONE_IP} \"{check_cmd}\"")
    if not result or result.stdout.strip() != "exists":
        cmd = """
if ! grep -q 'omni-project-status' ~/.bashrc 2>/dev/null; then
    echo '' >> ~/.bashrc
    echo '# UOM project status command alias' >> ~/.bashrc
    echo 'alias omni-project-status="/data/data/com.termux/files/usr/bin/sh ~/bin/omni-project-status"' >> ~/.bashrc
    echo 'alias uom-status="/src/universal-omni-master/bin/omni-orchestrator-monitor.sh"' >> ~/.bashrc
fi
"""
        result = run_command(f"ssh -o ConnectTimeout=5 -p {PHONE_PORT} {PHONE_USER}@{PHONE_IP} \"{cmd}\"")
        if result and result.returncode == 0:
            print("✓ Alias added to ~/.bashrc")
            return True
        print("✗ Failed to add alias to .bashrc")
    else:
        print("✓ Alias already exists in ~/.bashrc")
    return True

def main():
    print("=== UOM Status Alias Deployment ===")
    print()
    
    # Check SSH connection
    if not check_ssh_connection():
        print("Exiting due to SSH connectivity issues")
        sys.exit(1)
    print()
    
    # Create monitor script
    print("Creating monitor script on phone...")
    if not create_monitor_script():
        print("Exiting due to monitor script creation failure")
        sys.exit(1)
    print()
    
    # Create launcher script
    print("Creating launcher script in ~/bin/...")
    if not create_launcher():
        print("Exiting due to launcher script creation failure")
        sys.exit(1)
    print()
    
    # Add alias to shell config
    print("Adding alias to shell configuration...")
    if not add_alias():
        print("Exiting due to alias addition failure")
        sys.exit(1)
    print()
    
    print("=== Deployment Complete ===")
    print()
    print("Created on phone:")
    print("  1. /src/omni-project-status.sh - Main status monitoring script")
    print("  2. ~/bin/omni-project-status - Alias command to run monitor")
    print("  3. ~/bin/uom-status - UOM status shortcut")
    print()
    print("Access status on laptop with:")
    print("  omni-project-status        - Quick status summary")
    print("  omni-project-status --full  - Full status with logs")
    print("  omni-project-status tunnel  - Check tunnel status")
    print("  omni-project-status current - Show current mode")
    print()
    print("To use the alias on phone:")
    print(f"  ssh -p {PHONE_PORT} {PHONE_USER}@{{PHONE_IP}}")
    print("  Then run: omni-project-status")

if __name__ == "__main__":
    main()
