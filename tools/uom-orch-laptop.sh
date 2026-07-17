#!/bin/sh
# tools/uom-orch-laptop.sh — Laptop-side UOM loop orchestrator (dynamic IPs)
# HP Pavilion 15-n010tx / Alpine Linux / POSIX sh
# Usage: tmux new -s orch 'cd ~/src/universal-omni-master && sh tools/uom-orch-laptop.sh'

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
export PATH="$HOME/.opencode/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin"
. "$OMNI_ROOT/tools/uom-orch-state.sh"
. "$OMNI_ROOT/tools/uom-ip-discover.sh"

AGENT="laptop"
LOOP_SLEEP=60
OPENCODE_TIMEOUT=1800

_log() { printf '[%s] [LAPTOP] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

_announce_ip() {
    _my_ip=$(get_my_ip)
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/laptop.ip"
    chown "$(id -un)" "$OMNI_ROOT/.uom-agent/laptop.ip" 2>/dev/null || true
}

# ── Dynamic phone SSH target ─────────────────────────────────────────────
_phone_ssh_cmd() {
    # Returns: SSH command prefix for connecting to phone
    # Priority: reverse tunnel > direct LAN > mDNS > last-known

    # Method 1: reverse tunnel (always 127.0.0.1:18022)
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -p 18022 127.0.0.1 true 2>/dev/null; then
        printf '%s' "-F ~/.ssh/config -p 18022 uom-phone-rev"
        return 0
    fi

    # Method 2: mDNS
    if command -v avahi-resolve >/dev/null 2>&1; then
        _mdns_ip=$(avahi-resolve -n mi8.local 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$_mdns_ip" ] && [ "$_mdns_ip" != "0.0.0.0" ]; then
            printf '%s' "-F ~/.ssh/config -p 8022 u0_a608@${_mdns_ip}"
            return 0
        fi
    fi

    # Method 3: last known phone IP
    _pip=$(cat "$OMNI_ROOT/.uom-agent/phone.ip" 2>/dev/null)
    if [ -n "$_pip" ]; then
        _host=$(echo "$_pip" | sed 's/:.*//')
        _port=$(echo "$_pip" | grep -q ':' && echo "$_pip" | sed 's/.*://' || echo "8022")
        if ping -c 1 -W 2 "$_host" >/dev/null 2>&1; then
            printf '%s' "-F ~/.ssh/config -p $_port u0_a608@${_host}"
            return 0
        fi
    fi

    # Method 4: SSH config aliases
    for _alias in uom-phone-lan uom-phone-mdns; do
        if ssh -o ConnectTimeout=3 -o BatchMode=yes -G "$_alias" >/dev/null 2>&1; then
            printf '%s' "-F ~/.ssh/config $_alias"
            return 0
        fi
    done

    return 1
}

# ── Sync phone IP + SSH config on network change ─────────────────────────
_sync_phone_ssh() {
    _phone_ip=$(discover_phone_ip) || return
    [ -z "$_phone_ip" ] && return

    # Strip port if present for state file
    _host=$(echo "$_phone_ip" | sed 's/:.*//')
    echo "$_host" > "$OMNI_ROOT/.uom-agent/phone.ip"

    # Update laptop.ip state file too
    _my_ip=$(get_my_ip)
    [ -n "$_my_ip" ] && echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/laptop.ip"
}

_run_opencode() {
    _task_id="$1"; _task_desc="$2"; _context="$3"
    _prompt="You are working on the Universal Omni-Master (UOM) project.
Task ID: $_task_id
Task: $_task_desc

POSIX-ONLY RULES (non-negotiable):
- #!/bin/sh everywhere. Zero bashisms. Zero eval. Zero 'set --'.
- BusyBox ash-safe. All files pass: sh -n <file>
- Mutation guard: exit 126 when OMNI_SYSROOT is set.
- Reference OS: Alpine Linux 3.x (musl, OpenRC).

${_context}

Implement the task. Output complete file paths and full file contents."

    _log "Running opencode: $_task_id"
    printf '%s\n' "$_prompt" | timeout "$OPENCODE_TIMEOUT" opencode 2>&1
    return $?
}

main() {
    _log "UOM Laptop Orchestrator starting. OMNI_ROOT=$OMNI_ROOT"
    state_init

    while true; do
        if ! net_ok; then
            _log "Offline. Waiting ${LOOP_SLEEP}s..."; sleep "$LOOP_SLEEP"; continue
        fi

        state_git_pull
        _announce_ip
        _sync_phone_ssh
        state_heartbeat "$AGENT"

        # Defer if phone is actively working
        _active=$(state_get "active_agent")
        _status=$(state_get "task_status")
        if [ "$_active" = "phone" ] && [ "$_status" = "in_progress" ]; then
            _log "Phone is working. Deferring."
            state_git_sync "heartbeat: laptop alive, deferring $(date -Iseconds)"
            sleep "$LOOP_SLEEP"; continue
        fi

        _task_id=$(state_next_task)
        if [ -z "$_task_id" ]; then
            _log "No pending tasks. Idle."
            state_git_sync "heartbeat: laptop idle $(date -Iseconds)"
            sleep "$LOOP_SLEEP"; continue
        fi

        _task_desc=$(state_task_desc "$_task_id")
        _context=$(state_task_context "$_task_id")

        _log "Starting: $_task_id — $_task_desc"
        state_mark_task "$_task_id" "in_progress"
        state_set "current_task_id" "$_task_id"
        state_set "task_status" "in_progress"
        state_git_sync "start: $_task_id [$AGENT]"

        _out="${TMPDIR:-/tmp}/uom-oc-laptop-$$.txt"
        if _run_opencode "$_task_id" "$_task_desc" "$_context" > "$_out" 2>&1; then
            _log "Completed: $_task_id"
            cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-output.md" 2>/dev/null
            state_mark_task "$_task_id" "done"
            state_set "task_status" "done"
            state_git_sync "done: $_task_id [$AGENT]"
        else
            _rc=$?
            _log "FAILED: $_task_id (exit $_rc)"
            cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-error.md" 2>/dev/null
            state_mark_task "$_task_id" "failed"
            state_set "task_status" "failed"
            state_git_sync "failed: $_task_id [$AGENT] rc=$_rc"
        fi
        rm -f "$_out"
        sleep 5
    done
}

main "$@"
