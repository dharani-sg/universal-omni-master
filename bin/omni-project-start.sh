#!/bin/sh
# bin/omni-project-start.sh — UOM Project Start Menu
# Interactive dashboard + mode switching for dual-agent orchestrator
# Works on both Alpine (laptop) and Termux (phone).
# 
# Usage:
#   omni-project-start            Interactive menu
#   omni-project-start --menu     Same
#   omni-project-start status     Dashboard + exit
#   omni-project-start detach     Force phone takeover (detach from laptop)
#   omni-project-start phone      Switch primary agent to phone
#   omni-project-start laptop     Switch primary agent to laptop
#   omni-project-start hybrid     Hybrid auto-orchestrator mode
#   omni-project-start aware      Intelligent switching / situation awareness
#   omni-project-start tmux       Start/attach tmux session
#   omni-project-start opencode   Launch opencode
#   omni-project-start recover    Recover stuck in_progress tasks
#   omni-project-start test       Test tunnel + connectivity

set -u

UOM_DIR="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
STATE_FILE="${UOM_DIR}/.uom-agent/state.json"
QUEUE_FILE="${UOM_DIR}/.uom-agent/queue.json"
DONE_FILE="${UOM_DIR}/.uom-agent/done.json"
HYB_DIR="${HOME}/.uom-termux-user"
TUNNEL_LOG="${HYB_DIR}/tunnel.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ -f "${UOM_DIR}/tools/uom-orch-state.sh" ]; then
    . "${UOM_DIR}/tools/uom-orch-state.sh"
fi
if [ -f "${UOM_DIR}/tools/uom-ip-discover.sh" ]; then
    . "${UOM_DIR}/tools/uom-ip-discover.sh"
fi

# ── Detect platform ────────────────────────────────────────────────────
IS_PHONE=false
if echo "$HOME" | grep -q '/data/data/com.termux' 2>/dev/null; then
    IS_PHONE=true
fi

_log() {
    _ts=$(date -u +"%H:%M:%S" 2>/dev/null || date -u)
    printf '[start] %s %s\n' "${_ts}" "$*"
}

# ═══════════════════════════════════════════════════════════════════════
# DASHBOARD
# ═══════════════════════════════════════════════════════════════════════

_status_dashboard() {
    _ts=$(date)
    
    # ── State ──────────────────────────────────────────────────────
    if [ -f "$STATE_FILE" ]; then
        _active=$(jq -r '.active_agent // "unknown"' "$STATE_FILE" 2>/dev/null)
        _task_status=$(jq -r '.task_status // "idle"' "$STATE_FILE" 2>/dev/null)
        _task_id=$(jq -r '.current_task_id // "none"' "$STATE_FILE" 2>/dev/null)
        _lh=$(jq -r '.laptop_heartbeat // ""' "$STATE_FILE" 2>/dev/null)
        _ph=$(jq -r '.phone_heartbeat // ""' "$STATE_FILE" 2>/dev/null)
        _takeover=$(jq -r '.takeover_count // 0' "$STATE_FILE" 2>/dev/null)
        _queue_total=$(jq -r 'length' "$QUEUE_FILE" 2>/dev/null || echo "0")
        _queue_pending=$(jq -r '[.[] | select(.status=="pending")] | length' "$QUEUE_FILE" 2>/dev/null || echo "0")
        _queue_failed=$(jq -r '[.[] | select(.status=="failed")] | length' "$QUEUE_FILE" 2>/dev/null || echo "0")
        _queue_done=$(jq -r '[.[] | select(.status=="done")] | length' "$QUEUE_FILE" 2>/dev/null || echo "0")
        _queue_inprog=$(jq -r '[.[] | select(.status=="in_progress")] | length' "$QUEUE_FILE" 2>/dev/null || echo "0")
    else
        _active="no-state"; _task_status=""; _task_id=""; _lh=""; _ph=""
        _takeover="0"; _queue_total="0"; _queue_pending="0"
        _queue_failed="0"; _queue_done="0"; _queue_inprog="0"
    fi

    # ── Tunnel ─────────────────────────────────────────────────────
    if pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1 || pgrep -f 'ssh.*-R.*31415' >/dev/null 2>&1; then
        _tunnel="${GREEN}✓ UP (autossh)${NC}"
    elif ssh -F ~/.ssh/config -o ConnectTimeout=2 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
        _tunnel="${GREEN}✓ UP (port 31415)${NC}"
    else
        _tunnel="${RED}✗ DOWN${NC}"
    fi

    # ── Processes ──────────────────────────────────────────────────
    _orch_laptop=$(ps -ef 2>/dev/null | grep -v grep | grep -q 'uom-orch-laptop' && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}")
    _orch_phone=$(ps -ef 2>/dev/null | grep -v grep | grep -q 'uom-orch-phone' && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}")
    _tmux_uom=$(tmux has-session -t uom 2>/dev/null && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}")
    _tmux_hybrid=$(tmux has-session -t uom-hybrid 2>/dev/null && echo "${GREEN}✓${NC}" || echo "${RED}✗${NC}")

    # ── Next task ──────────────────────────────────────────────────
    _next_id=$(jq -r '[.[] | select(.status=="pending")] | first | .id // empty' "$QUEUE_FILE" 2>/dev/null)
    _next_desc=""
    [ -n "$_next_id" ] && _next_desc=$(jq -r --arg id "$_next_id" '.[] | select(.id==$id) | .desc // ""' "$QUEUE_FILE" 2>/dev/null)

    # ── Network ────────────────────────────────────────────────────
    _my_ip=$(get_my_ip 2>/dev/null || echo "unknown")
    if net_ok 2>/dev/null; then
        _net="${GREEN}ONLINE${NC} (${_my_ip})"
    else
        _net="${RED}OFFLINE${NC}"
    fi

    # ── Render dashboard ───────────────────────────────────────────
    printf '\n'
    printf '╔══════════════════════════════════════════════════════════════╗\n'
    printf '║               %sUOM PROJECT START MENU%s                  ║\n' "$BOLD" "$NC"
    printf '╠══════════════════════════════════════════════════════════════╣\n'
    printf '║ %-60s ║\n' "TIMESTAMP: ${_ts}"
    if $IS_PHONE; then
        printf '║ %-60s ║\n' "PLATFORM:  ${BOLD}PHONE${NC} (Termux/Android)"
    else
        printf '║ %-60s ║\n' "PLATFORM:  ${BOLD}LAPTOP${NC} (Alpine Linux)"
    fi
    printf '║ %-60s ║\n' "NETWORK:   ${_net}"
    printf '╠══════════════════════════════════════════════════════════════╣\n'
    printf '║ %-60s ║\n' "STATUS DASHBOARD:"
    printf '║   %-57s ║\n' "Active Agent: ${BOLD}${_active}${NC}"
    printf '║   %-57s ║\n' "Task Status:  ${_task_status}"
    printf '║   %-57s ║\n' "Current Task: ${_task_id}"
    printf '║   %-57s ║\n' "Reverse Tunnel: ${_tunnel}"
    printf '║   %-57s ║\n' "Queue: ${_queue_pending} pending, ${_queue_inprog} in-prog, ${_queue_done} done, ${_queue_failed} failed"
    printf '║   %-57s ║\n' "Takeover Count: ${_takeover}"
    printf '║   %-57s ║\n' "Laptop  HB: ${_lh:-none}"
    printf '║   %-57s ║\n' "Phone   HB: ${_ph:-none}"
    printf '║ %-60s ║\n' "Processes: laptop-orch ${_orch_laptop}  phone-orch ${_orch_phone}  tmux-uom ${_tmux_uom}  tmux-hybrid ${_tmux_hybrid}"
    if [ -n "$_next_id" ]; then
        printf '║ %-60s ║\n' "NEXT TASK: ${BOLD}${_next_id}${NC} — ${_next_desc}"
        printf '║ %-60s ║\n' "  → Run: omni-project-start opencode  (or just: opencode)"
    fi
    printf '╠══════════════════════════════════════════════════════════════╣\n'
    printf '║ %-60s ║\n' "${BOLD}ACTIONS:${NC}"
    printf '║   %-57s ║\n' "1) Status Dashboard (detailed)"
    printf '║   %-57s ║\n' "2) Detach from Laptop (force phone takeover)"
    printf '║   %-57s ║\n' "3) Run from Phone (switch primary to phone)"
    printf '║   %-57s ║\n' "4) Run from Laptop (switch primary to laptop)"
    printf '║   %-57s ║\n' "5) Hybrid Auto-Orchestrator Mode"
    printf '║   %-57s ║\n' "6) Intelligent Switching (situation awareness)"
    printf '║   %-57s ║\n' "7) Start / Attach Tmux Session"
    printf '║   %-57s ║\n' "8) Start opencode (AI coding agent)"
    printf '║   %-57s ║\n' "9) Test Tunnel + Connectivity"
    printf '║   %-57s ║\n' "r) Recover stuck in_progress tasks"
    printf '║   %-57s ║\n' "q) Quit"
    printf '╚══════════════════════════════════════════════════════════════╝\n'
    printf '\n'
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Detach from Laptop
# ═══════════════════════════════════════════════════════════════════════

action_detach() {
    _log "Detaching from laptop — forcing phone takeover..."
    
    if ! $IS_PHONE; then
        _log "This action must be run from the PHONE side."
        _log "The laptop cannot detach from itself."
        _log "SSH to phone and run: omni-project-start detach"
        return 1
    fi

    # Kill tunnel (phone side)
    _log "Stopping reverse tunnel..."
    pkill -f 'autossh.*-R.*31415' 2>/dev/null || true
    pkill -f 'ssh.*-R.*31415' 2>/dev/null || true
    sleep 2

    # Try to disable laptop orchestrator via direct SSH
    _log "Stopping laptop orchestrator remotely..."
    _lip="${UOM_LAPTOP_IP:-192.168.40.90}"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "${UOM_LAPTOP_USER:-alpine}@${_lip}" \
        "pkill -f uom-orch-laptop 2>/dev/null; echo 'laptop orch stopped'" \
        2>/dev/null || true

    # Set state to phone primary
    state_set "active_agent" "phone"
    state_set "task_status" "idle"
    state_set "current_task_id" ""
    state_git_sync "detach: phone takeover forced"
    _log "State set to phone primary."

    # Start phone orchestrator in active mode if not running
    if ! ps -ef 2>/dev/null | grep -v grep | grep -q uom-orch-phone; then
        _log "Starting phone orchestrator..."
        nohup sh "${UOM_DIR}/tools/uom-orch-phone.sh" > "${HYB_DIR}/phone-orch.log" 2>&1 &
        _log "Phone orchestrator started (PID $!)"
    fi

    _log "=== DETACH COMPLETE ==="
    _log "Phone is now primary agent."
    _log "To verify: omni-project-start status"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Switch to Phone Primary
# ═══════════════════════════════════════════════════════════════════════

action_phone() {
    _log "Switching primary agent to phone..."
    
    if [ ! -f "$STATE_FILE" ]; then
        _log "ERROR: State file not found at $STATE_FILE"
        return 1
    fi

    state_set "active_agent" "phone"
    state_git_sync "switch: phone primary"
    _log "Active agent set to phone."
    _log ""
    _log "Laptop orchestrator will defer on next heartbeat."
    _log "If phone is not running orchestrator, start it:"
    _log "  ssh u0_a608@192.168.40.207 'cd ~/src/universal-omni-master && sh tools/uom-orch-phone.sh'"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Switch to Laptop Primary
# ═══════════════════════════════════════════════════════════════════════

action_laptop() {
    _log "Switching primary agent to laptop..."
    
    if [ ! -f "$STATE_FILE" ]; then
        _log "ERROR: State file not found"
        return 1
    fi

    state_set "active_agent" "laptop"
    state_git_sync "switch: laptop primary"
    _log "Active agent set to laptop."
    _log ""
    _log "Phone will detect heartbeat and return to watchdog mode."
    _log "If laptop orchestrator is not running, start it:"
    _log "  cd ~/src/universal-omni-master && sh tools/uom-orch-laptop.sh"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Hybrid Mode
# ═══════════════════════════════════════════════════════════════════════

action_hybrid() {
    _log "Starting Hybrid Auto-Orchestrator Mode..."

    _hybrid_script="${UOM_DIR}/bin/uom-hybrid.sh"
    if [ ! -f "$_hybrid_script" ]; then
        _log "ERROR: $_hybrid_script not found"
        return 1
    fi

    # Check if already running in tmux
    if tmux has-session -t uom-hybrid 2>/dev/null; then
        _log "Hybrid session already exists. Attaching..."
        tmux attach-session -t uom-hybrid
        return 0
    fi

    _log "Creating hybrid tmux session..."
    sh "$_hybrid_script" --daemon
    _log "Hybrid session created. Attaching..."
    sleep 1
    tmux attach-session -t uom-hybrid
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Intelligent Switching (Situation Awareness)
# ═══════════════════════════════════════════════════════════════════════

action_aware() {
    printf '\n'
    printf '╔══════════════════════════════════════════════════════════════╗\n'
    printf '║        INTELLIGENT SWITCHING — SITUATION AWARENESS          ║\n'
    printf '╠══════════════════════════════════════════════════════════════╣\n'

    # ── Check environment ──────────────────────────────────────────
    printf '║ %-60s ║\n' "1. ENVIRONMENT CHECK"
    
    if $IS_PHONE; then
        printf '║   %-57s ║\n' "Running on: ${BOLD}PHONE${NC} (Termux/Android)"
    else
        printf '║   %-57s ║\n' "Running on: ${BOLD}LAPTOP${NC} (Alpine Linux)"
    fi

    # ── Network ────────────────────────────────────────────────────
    printf '║ %-60s ║\n' "2. NETWORK CHECK"
    if net_ok 2>/dev/null; then
        printf '║   %-57s ║\n' "Internet: ${GREEN}CONNECTED${NC}"
    else
        printf '║   %-57s ║\n' "Internet: ${RED}DISCONNECTED${NC}"
    fi
    _my_ip=$(get_my_ip 2>/dev/null || echo "unknown")
    printf '║   %-57s ║\n' "My IP: ${_my_ip}"

    # ── Tunnel check ───────────────────────────────────────────────
    printf '║ %-60s ║\n' "3. REVERSE TUNNEL CHECK"
    _tunnel_found=false
    if pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1 || pgrep -f 'ssh.*-R.*31415' >/dev/null 2>&1; then
        printf '║   %-57s ║\n' "Tunnel process: ${GREEN}ALIVE${NC}"
        _tunnel_found=true
    fi
    if ssh -F ~/.ssh/config -o ConnectTimeout=2 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
        printf '║   %-57s ║\n' "Tunnel reachable: ${GREEN}YES${NC} (laptop:31415→phone:8022)"
        _tunnel_found=true
    fi
    if ! $_tunnel_found; then
        printf '║   %-57s ║\n' "Tunnel: ${RED}DOWN${NC}"
    fi

    # ── Laptop reachability ────────────────────────────────────────
    printf '║ %-60s ║\n' "4. LAPTOP REACHABILITY"
    _laptop_reachable=false
    for _lip in 192.168.40.90 192.168.43.90; do
        if ping -c 1 -W 2 "$_lip" >/dev/null 2>&1; then
            printf '║   %-57s ║\n' "LAN ping: ${GREEN}${_lip}${NC}"
            _laptop_reachable=true
            break
        fi
    done
    if ! $_laptop_reachable; then
        # Check SSH config alias
        if ssh -o ConnectTimeout=3 -o BatchMode=yes -G uom-laptop-lan >/dev/null 2>&1; then
            printf '║   %-57s ║\n' "SSH config: ${YELLOW}found but not pingable${NC}"
        else
            printf '║   %-57s ║\n' "LAN: ${RED}UNREACHABLE${NC}"
        fi
    fi

    # ── Phone reachability (from laptop) ───────────────────────────
    if ! $IS_PHONE; then
        printf '║ %-60s ║\n' "5. PHONE REACHABILITY"
        if ssh -F ~/.ssh/config -o ConnectTimeout=3 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
            printf '║   %-57s ║\n' "Reverse tunnel: ${GREEN}CONNECTED${NC}"
        elif ssh -F ~/.ssh/config -o ConnectTimeout=3 -o BatchMode=yes uom-phone-lan true 2>/dev/null; then
            printf '║   %-57s ║\n' "LAN SSH: ${GREEN}CONNECTED${NC}"
        else
            printf '║   %-57s ║\n' "Phone: ${RED}UNREACHABLE${NC}"
        fi
    fi

    # ── Heartbeat check ────────────────────────────────────────────
    printf '║ %-60s ║\n' "6. HEARTBEAT / STATE CHECK"
    if [ -f "$STATE_FILE" ]; then
        _lh=$(jq -r '.laptop_heartbeat // ""' "$STATE_FILE" 2>/dev/null)
        _ph=$(jq -r '.phone_heartbeat // ""' "$STATE_FILE" 2>/dev/null)
        _active=$(jq -r '.active_agent // "unknown"' "$STATE_FILE" 2>/dev/null)
        printf '║   %-57s ║\n' "Active agent: ${BOLD}${_active}${NC}"
        printf '║   %-57s ║\n' "Laptop  HB: ${_lh:-none}"
        printf '║   %-57s ║\n' "Phone   HB: ${_ph:-none}"
        
        # Check staleness
        _now=$(date -u +%s 2>/dev/null)
        if [ -n "$_lh" ]; then
            _lh_epoch=$(date -u -d "$_lh" +%s 2>/dev/null || python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$_lh').timestamp()))" 2>/dev/null || echo "0")
            _lh_diff=$(( _now - _lh_epoch ))
            if [ "$_lh_diff" -gt 300 ]; then
                printf '║   %-57s ║\n' "Laptop HB: ${RED}STALE (${_lh_diff}s ago)${NC}"
            else
                printf '║   %-57s ║\n' "Laptop HB: ${GREEN}FRESH (${_lh_diff}s ago)${NC}"
            fi
        fi
    fi

    # ── Recommendation ─────────────────────────────────────────────
    printf '╠══════════════════════════════════════════════════════════════╣\n'
    printf '║ %-60s ║\n' "${BOLD}RECOMMENDATION:${NC}"

    if $IS_PHONE; then
        if $_laptop_reachable; then
            printf '║   %-57s ║\n' "Laptop is LAN-reachable. Stay in ${BOLD}WATCHDOG${NC} mode."
            printf '║   %-57s ║\n' "Laptop orchestrator should manage tasks."
            printf '║   %-57s ║\n' "→ Run: omni-project-start hybrid"
        elif $_tunnel_found; then
            printf '║   %-57s ║\n' "Tunnel is up but laptop not on LAN."
            printf '║   %-57s ║\n' "Laptop orchestrator may be working through tunnel."
            printf '║   %-57s ║\n' "→ Check laptop HB; if stale, take over."
        else
            printf '║   %-57s ║\n' "Laptop is ${RED}UNREACHABLE${NC}. Phone should take over."
            printf '║   %-57s ║\n' "→ Run: omni-project-start detach"
        fi
    else
        # Running on laptop
        if $_tunnel_found; then
            printf '║   %-57s ║\n' "Tunnel is up. Phone is reachable via reverse tunnel."
            printf '║   %-57s ║\n' "Stay in ${BOLD}PRIMARY LAPTOP${NC} mode."
            printf '║   %-57s ║\n' "→ Run: omni-project-start to see tasks"
        else
            printf '║   %-57s ║\n' "Tunnel is ${RED}DOWN${NC}. Phone may be offline."
            printf '║   %-57s ║\n' "Try direct LAN SSH or wait for tunnel."
            printf '║   %-57s ║\n' "→ Run: omni-project-start test"
        fi
    fi
    printf '╚══════════════════════════════════════════════════════════════╝\n'
    printf '\n'
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Tmux Session Management
# ═══════════════════════════════════════════════════════════════════════

action_tmux() {
    _session="${1:-uom}"

    if ! command -v tmux >/dev/null 2>&1; then
        _log "ERROR: tmux not installed"
        return 1
    fi

    if tmux has-session -t "$_session" 2>/dev/null; then
        _log "Session '${_session}' exists. Attaching..."
        tmux attach-session -t "$_session"
        return 0
    fi

    # Create default session with project windows
    _log "Creating new tmux session '${_session}'..."
    tmux new-session -d -s "$_session" -n "start" "cd ${UOM_DIR} && sh bin/omni-project-start.sh --menu"
    sleep 0.5

    tmux new-window -t "$_session" -n "opencode" "cd ${UOM_DIR} && opencode"
    sleep 0.3

    tmux new-window -t "$_session" -n "status" "watch -n10 'sh ${UOM_DIR}/bin/uom-status.sh'"
    sleep 0.3

    tmux new-window -t "$_session" -n "state" "cd ${UOM_DIR} && watch -n5 'cat .uom-agent/state.json'"
    sleep 0.3

    tmux new-window -t "$_session" -n "git" "cd ${UOM_DIR} && git log --oneline --graph -20"
    sleep 0.3

    if $IS_PHONE; then
        tmux new-window -t "$_session" -n "laptop-ssh" "ssh -F ~/.ssh/config uom-laptop-rev"
    else
        tmux new-window -t "$_session" -n "phone-ssh" "ssh -F ~/.ssh/config uom-phone-rev"
    fi

    tmux select-window -t "$_session:0"
    tmux attach-session -t "$_session"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Start opencode
# ═══════════════════════════════════════════════════════════════════════

action_opencode() {
    if ! command -v opencode >/dev/null 2>&1; then
        _log "ERROR: opencode not found in PATH"
        _log "Install: curl -fsSL https://opencode.ai/install.sh | sh"
        return 1
    fi

    _log "Starting opencode in ${UOM_DIR}..."
    cd "$UOM_DIR" && exec opencode
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Test Connectivity
# ═══════════════════════════════════════════════════════════════════════

action_test() {
    printf '\n'
    printf '╔══════════════════════════════════════════════════════════════╗\n'
    printf '║             CONNECTIVITY TEST SUITE                        ║\n'
    printf '╠══════════════════════════════════════════════════════════════╣\n'

    # 1. Internet
    printf '║ %-60s ║\n' "1. INTERNET ACCESS"
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        printf '║   %-57s ║\n' "8.8.8.8: ${GREEN}PASS${NC}"
    else
        printf '║   %-57s ║\n' "8.8.8.8: ${RED}FAIL${NC}"
    fi
    if ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        printf '║   %-57s ║\n' "github.com: ${GREEN}PASS${NC}"
    else
        printf '║   %-57s ║\n' "github.com: ${RED}FAIL${NC}"
    fi

    # 2. Local network
    printf '║ %-60s ║\n' "2. LOCAL NETWORK"
    _my_ip=$(get_my_ip 2>/dev/null || echo "unknown")
    printf '║   %-57s ║\n' "My IP: ${_my_ip}"
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    printf '║   %-57s ║\n' "Gateway: ${_gw:-unknown}"

    # 3. Reverse tunnel
    printf '║ %-60s ║\n' "3. REVERSE TUNNEL (phone:31415↔laptop:8022)"
    if pgrep -f 'autossh.*-R.*31415' >/dev/null 2>&1; then
        printf '║   %-57s ║\n' "Autossh: ${GREEN}PASS${NC} (running)"
    else
        printf '║   %-57s ║\n' "Autossh: ${RED}FAIL${NC} (not running)"
    fi
    if ssh -F ~/.ssh/config -o ConnectTimeout=3 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
        printf '║   %-57s ║\n' "Connect: ${GREEN}PASS${NC} (laptop:31415→phone:8022)"
    else
        printf '║   %-57s ║\n' "Connect: ${RED}FAIL${NC}"
    fi

    # 4. SSH configs
    printf '║ %-60s ║\n' "4. SSH CONFIG ALIASES"
    for _alias in uom-phone-rev uom-phone-lan uom-phone-mdns uom-laptop-rev uom-laptop-lan; do
        if grep -q "^Host ${_alias}$" ~/.ssh/config 2>/dev/null; then
            printf '║   %-57s ║\n' "${_alias}: ${GREEN}configured${NC}"
        fi
    done

    # 5. Git
    printf '║ %-60s ║\n' "5. GIT REMOTE"
    if git -C "$UOM_DIR" remote -v >/dev/null 2>&1; then
        printf '║   %-57s ║\n' "Git remote: ${GREEN}OK${NC}"
        _remote=$(git -C "$UOM_DIR" remote get-url origin 2>/dev/null)
        printf '║   %-57s ║\n' "  ${_remote}"
        if git -C "$UOM_DIR" ls-remote origin HEAD >/dev/null 2>&1; then
            printf '║   %-57s ║\n' "Git push: ${GREEN}PASS${NC}"
        else
            printf '║   %-57s ║\n' "Git push: ${RED}FAIL${NC}"
        fi
    fi

    # 6. State file
    printf '║ %-60s ║\n' "6. STATE FILE INTEGRITY"
    if [ -f "$STATE_FILE" ]; then
        if jq -e '.' "$STATE_FILE" >/dev/null 2>&1; then
            printf '║   %-57s ║\n' "state.json: ${GREEN}VALID${NC}"
        else
            printf '║   %-57s ║\n' "state.json: ${RED}INVALID${NC}"
        fi
    else
        printf '║   %-57s ║\n' "state.json: ${RED}NOT FOUND${NC}"
    fi
    if [ -f "$QUEUE_FILE" ]; then
        if jq -e '.' "$QUEUE_FILE" >/dev/null 2>&1; then
            printf '║   %-57s ║\n' "queue.json: ${GREEN}VALID${NC}"
        else
            printf '║   %-57s ║\n' "queue.json: ${RED}INVALID${NC}"
        fi
    fi

    printf '╚══════════════════════════════════════════════════════════════╝\n'
    printf '\n'
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# ACTION: Recover stuck tasks
# ═══════════════════════════════════════════════════════════════════════

action_recover() {
    _log "Checking for stuck in_progress tasks..."
    
    _stuck=$(jq -r '[.[] | select(.status=="in_progress")] | length' "$QUEUE_FILE" 2>/dev/null || echo "0")
    if [ "$_stuck" -eq 0 ]; then
        _log "No stuck tasks found."
        return 0
    fi

    _stuck_ids=$(jq -r '[.[] | select(.status=="in_progress") | .id] | .[]' "$QUEUE_FILE" 2>/dev/null)
    _count=0
    for _id in $_stuck_ids; do
        _log "Found stuck: $_id"
        state_mark_task "$_id" "pending"
        _count=$(( _count + 1 ))
    done

    state_git_sync "recover: reset ${_count} stuck tasks to pending"
    _log "Reset ${_count} stuck task(s) to pending."
    _log "Run 'omni-project-start' to see next tasks."
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
# INTERACTIVE MENU
# ═══════════════════════════════════════════════════════════════════════

_menu_loop() {
    while true; do
        _status_dashboard
        printf '%s' "Enter choice [1-9, r, q]: "
        read -r _choice

        case "$_choice" in
            1|status)
                sh "${UOM_DIR}/bin/uom-status.sh"
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            2|detach)
                action_detach
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            3|phone)
                action_phone
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            4|laptop)
                action_laptop
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            5|hybrid)
                action_hybrid
                # If we return from tmux, show menu again
                ;;
            6|aware)
                action_aware
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            7|tmux)
                action_tmux
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            8|opencode)
                action_opencode
                # If opencode exits, return to menu
                ;;
            9|test)
                action_test
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            r|recover)
                action_recover
                printf '\n%s' "Press Enter to continue..."; read -r _
                ;;
            q|quit|exit)
                _log "Goodbye."
                exit 0
                ;;
            *)
                printf '\n%s' "Invalid choice. Press Enter to continue..."; read -r _
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════
# MAIN ENTRY
# ═══════════════════════════════════════════════════════════════════════

main() {
    _cmd="${1:-}"

    case "$_cmd" in
        --menu|-m|"")
            _menu_loop
            ;;
        status|--status|-s)
            _status_dashboard
            sh "${UOM_DIR}/bin/uom-status.sh" | tail -n +2
            ;;
        detach|--detach|-d)
            action_detach
            ;;
        phone|--phone|-p)
            action_phone
            ;;
        laptop|--laptop|-l)
            action_laptop
            ;;
        hybrid|--hybrid)
            action_hybrid
            ;;
        aware|--aware|situation|--situation)
            action_aware
            ;;
        tmux|--tmux)
            action_tmux
            ;;
        opencode|--opencode)
            action_opencode
            ;;
        test|--test|-t)
            action_test
            ;;
        recover|--recover|-r)
            action_recover
            ;;
        help|--help|-h)
            printf '\n'
            printf 'Usage: omni-project-start [COMMAND]\n'
            printf '\n'
            printf 'Commands:\n'
            printf '  (no args)    Interactive start menu (default)\n'
            printf '  status       Show dashboard + status\n'
            printf '  detach       Force phone takeover (run from phone)\n'
            printf '  phone        Switch primary agent to phone\n'
            printf '  laptop       Switch primary agent to laptop\n'
            printf '  hybrid       Start hybrid auto-orchestrator mode\n'
            printf '  aware        Intelligent switching / situation awareness\n'
            printf '  tmux         Start or attach tmux session\n'
            printf '  opencode     Launch opencode AI coding agent\n'
            printf '  test         Run connectivity test suite\n'
            printf '  recover      Reset stuck in_progress tasks to pending\n'
            printf '  help         Show this help\n'
            printf '\n'
            ;;
        *)
            printf 'Unknown command: %s\n' "$_cmd"
            printf 'Run: omni-project-start help\n'
            exit 1
            ;;
    esac
}

main "$@"
