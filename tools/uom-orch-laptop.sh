#!/bin/sh
# tools/uom-orch-laptop.sh — Laptop-side UOM loop orchestrator (dynamic IPs)
# HP Pavilion 15-n010tx / Alpine Linux / POSIX sh
# Usage: tmux new -s orch 'cd ~/src/universal-omni-master && sh tools/uom-orch-laptop.sh'

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
export PATH="$HOME/.opencode/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin"
. "$OMNI_ROOT/tools/uom-state-lib.sh"
. "$OMNI_ROOT/tools/uom-ip-discover.sh"

AGENT="laptop"
LOOP_SLEEP=60
OPENCODE_TIMEOUT=1800
_RECOVERY_MODE=0

_log() { printf '[%s] [LAPTOP] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

_announce_ip() {
    _my_ip=$(get_my_ip)
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/laptop.ip"
    chown "$(id -un)" "$OMNI_ROOT/.uom-agent/laptop.ip" 2>/dev/null || true
}

# ── Queue operations (using state-lib paths) ────────────────────────────

state_next_task() {
    jq -r '[.[] | select(.status=="pending")] | first | .id // empty' "$UOM_QUEUE_FILE" 2>/dev/null
}

state_task_desc() {
    jq -r --arg id "$1" '.[] | select(.id==$id) | .desc // empty' "$UOM_QUEUE_FILE" 2>/dev/null
}

state_task_context() {
    _ctx_file=$(jq -r --arg id "$1" '.[] | select(.id==$id) | .context_file // empty' "$UOM_QUEUE_FILE" 2>/dev/null)
    [ -n "$_ctx_file" ] && [ -f "${OMNI_ROOT}/$_ctx_file" ] && cat "${OMNI_ROOT}/$_ctx_file"
}

state_mark_task() {
    _id="$1"; _status="$2"
    _tmp="${UOM_QUEUE_FILE}.tmp"
    jq --arg id "$_id" --arg st "$_status" \
       'map(if .id==$id then .status=$st else . end)' \
       "$UOM_QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$UOM_QUEUE_FILE"
    if [ "$_status" = "done" ]; then
        _now=$(uom_now_utc)
        _tmp2="${UOM_DONE_FILE}.tmp"
        jq --arg id "$_id" --arg t "$_now" --arg a "$AGENT" \
           '. + [{"id":$id,"completed":$t,"by":$a}]' \
           "$UOM_DONE_FILE" > "$_tmp2" 2>/dev/null && mv "$_tmp2" "$UOM_DONE_FILE"
    fi
}

# ── Git operations (no auto-push) ──────────────────────────────────────

state_git_sync() {
    _msg="$1"
    cd "$OMNI_ROOT" || return 1
    git add .uom-agent/ 2>/dev/null
    git diff --cached --quiet && return 0
    git commit -m "$_msg" || return 1
}

state_git_pull() {
    cd "$OMNI_ROOT" || return 1
    _is_dirty=$(git status --porcelain 2>/dev/null | head -1)
    [ -n "$_is_dirty" ] && { _log "Worktree dirty — skipping pull"; return 0; }
    git pull --ff-only 2>/dev/null || _log "ff-only pull failed"
}

# ── Authority validation ───────────────────────────────────────────────

_validate_authority() {
    _mode=$(uom_state_get "active_agent")
    _writer=$(uom_state_get "writer_role")
    _epoch=$(uom_state_get "ownership_epoch")
    _lease_exp=$(uom_state_get "lease_expires_epoch")
    _now=$(uom_now_epoch)
    [ "$_mode" = "dual" ] || return 1
    [ "$_writer" = "laptop" ] || return 1
    [ "${_lease_exp:-0}" -gt "$_now" ] 2>/dev/null || return 1
    return 0
}

# ── Query phone authority via reverse tunnel ────────────────────────────

_query_phone_state() {
    _phone_json=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -p 31415 127.0.0.1 \
        "cat \$HOME/src/universal-omni-master/.uom-agent/state.json" 2>/dev/null) \
        || return 1
    [ -n "$_phone_json" ] && printf '%s\n' "$_phone_json"
}

# ── Startup recovery ───────────────────────────────────────────────────

startup_recovery() {
    _log "=== Startup recovery ==="
    cd "$OMNI_ROOT" || return 1

    _git_status=$(git status --short 2>/dev/null || echo 'unknown')
    _log "Git status: ${_git_status:-clean}"

    _has_upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || true
    _is_dirty=$(git status --porcelain 2>/dev/null | head -1)

    if [ -n "$_has_upstream" ] && [ -z "$_is_dirty" ]; then
        _log "Clean worktree, upstream exists — fetching"
        git fetch --quiet 2>/dev/null || _log "fetch failed"
        git pull --ff-only 2>/dev/null || _log "ff-only pull failed (non-ff or offline)"
    else
        [ -n "$_is_dirty" ] && _log "Worktree dirty — never pulling"
        [ -z "$_has_upstream" ] && _log "No upstream — skipping pull"
    fi

    _active_agent=$(uom_state_get "active_agent")
    _writer_role=$(uom_state_get "writer_role")
    _ownership_epoch=$(uom_state_get "ownership_epoch")
    _lease_id=$(uom_state_get "lease_id")
    _lease_expires=$(uom_state_get "lease_expires_epoch")
    _task_status=$(uom_state_get "task_status")
    _current_task_id=$(uom_state_get "current_task_id")
    _checkpoint_ref=$(uom_state_get "checkpoint_ref")

    _log "State: agent=$_active_agent writer=$_writer_role epoch=$_ownership_epoch task=$_task_status"

    if [ "$_task_status" = "in_progress" ] && [ -n "$_current_task_id" ]; then
        _log "Recovering in_progress task: $_current_task_id"
        uom_state_update_filter '.task_status = "pending"'
        _desc=$(jq -r --arg id "$_current_task_id" \
            '.[] | select(.id==$id) | .desc // empty' "$UOM_QUEUE_FILE" 2>/dev/null)
        if [ -n "$_desc" ]; then
            case "$_desc" in
                "RETRY: "*) ;;
                *) _desc="RETRY: ${_desc}" ;;
            esac
            _tmp="${UOM_QUEUE_FILE}.tmp"
            jq --arg id "$_current_task_id" --arg d "$_desc" \
                'map(if .id==$id then .desc=$d else . end)' \
                "$UOM_QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$UOM_QUEUE_FILE"
        fi
        _tmp="${UOM_QUEUE_FILE}.tmp"
        jq --arg id "$_current_task_id" \
            'map(if .id==$id then .status="pending" else . end)' \
            "$UOM_QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$UOM_QUEUE_FILE"
        state_git_sync "recovery: $_current_task_id in_progress→pending"
    fi

    if [ "$_task_status" = "checkpointed" ] && [ -n "$_current_task_id" ]; then
        _log "Recovering checkpointed task: $_current_task_id (ref=$_checkpoint_ref)"
        uom_state_update_filter '.task_status = "pending"'
        _tmp="${UOM_QUEUE_FILE}.tmp"
        jq --arg id "$_current_task_id" \
            'map(if .id==$id then .status="pending" else . end)' \
            "$UOM_QUEUE_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$UOM_QUEUE_FILE"
        state_git_sync "recovery: $_current_task_id checkpointed→pending"
    fi

    _phone_reachable=0
    _phone_agent=""
    _phone_json=$(_query_phone_state) && {
        _phone_reachable=1
        _phone_agent=$(printf '%s\n' "$_phone_json" | jq -r '.active_agent // empty' 2>/dev/null)
        _phone_writer=$(printf '%s\n' "$_phone_json" | jq -r '.writer_role // empty' 2>/dev/null)
        _log "Phone reachable: agent=$_phone_agent writer=$_phone_writer"
    }

    if [ "$_phone_reachable" -eq 1 ] && [ "$_phone_agent" = "phone-solo" ]; then
        _log "Phone claims phone-solo — yielding control"
        uom_state_update_filter '.active_agent = "phone-solo" | .writer_role = "phone"'
        state_git_sync "recovery: yielding to phone-solo"
        return 1
    fi

    _active_agent=$(uom_state_get "active_agent")
    _writer_role=$(uom_state_get "writer_role")
    _lease_expires=$(uom_state_get "lease_expires_epoch")
    _now=$(uom_now_epoch)

    if [ "$_active_agent" != "dual" ] || [ "$_writer_role" != "laptop" ]; then
        if [ "$_phone_reachable" -eq 0 ]; then
            _log "Phone unreachable, authority uncertain — fail closed, read-only"
            _RECOVERY_MODE=1
            return 0
        fi
        _log "Authority invalid: agent=$_active_agent writer=$_writer_role"
        _RECOVERY_MODE=1
        return 0
    fi

    if [ "${_lease_expires:-0}" -le "$_now" ] 2>/dev/null; then
        _log "Lease expired — read-only recovery"
        _RECOVERY_MODE=1
        return 0
    fi

    _log "Authority OK: dual/laptop epoch=$_ownership_epoch lease_valid"
    return 0
}

# ── Dynamic phone SSH target ─────────────────────────────────────────────
_phone_ssh_cmd() {
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -p 31415 127.0.0.1 true 2>/dev/null; then
        printf '%s' "-F ~/.ssh/config -p 31415 uom-phone-rev"
        return 0
    fi

    if command -v avahi-resolve >/dev/null 2>&1; then
        _mdns_ip=$(avahi-resolve -n mi8.local 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$_mdns_ip" ] && [ "$_mdns_ip" != "0.0.0.0" ]; then
            printf '%s' "-F ~/.ssh/config -p 8022 u0_a608@${_mdns_ip}"
            return 0
        fi
    fi

    _pip=$(cat "$OMNI_ROOT/.uom-agent/phone.ip" 2>/dev/null)
    if [ -n "$_pip" ]; then
        _host=$(echo "$_pip" | sed 's/:.*//')
        _port=$(echo "$_pip" | grep -q ':' && echo "$_pip" | sed 's/.*://' || echo "31415")
        if ping -c 1 -W 2 "$_host" >/dev/null 2>&1; then
            printf '%s' "-F ~/.ssh/config -p $_port u0_a608@${_host}"
            return 0
        fi
    fi

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
    _host=$(echo "$_phone_ip" | sed 's/:.*//')
    echo "$_host" > "$OMNI_ROOT/.uom-agent/phone.ip"
    _my_ip=$(get_my_ip)
    [ -n "$_my_ip" ] && echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/laptop.ip"
}

# ── Clean stale SSH port forward on laptop side ──────────────────────────
_clean_laptop_tunnel_port() {
    _laptop_user="${UOM_LAPTOP_USER:-alpine}"
    for _target in "-p 31415 u0_a608@127.0.0.1" "alpine@192.168.40.90"; do
        ssh -o ConnectTimeout=3 -o BatchMode=yes $_target \
            "pgrep -f 'sshd:.*@notty' | while read pid; do
                 port=\$(ss -tlnp 2>/dev/null | grep 31415 | grep -o 'pid=\$pid' || true)
                 [ -n \"\$port\" ] && kill \$pid 2>/dev/null && echo 'killed stale sshd \$pid'
             done
             if ss -tlnp 2>/dev/null | grep -q 31415; then
                 echo 'port 31415 still held — force kill sshd children holding it'
                 fuser -k 31415/tcp 2>/dev/null || true
             fi
             echo 'tunnel port cleaned'" 2>/dev/null && return 0
    done
    return 1
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
    uom_state_init

    if ! startup_recovery; then
        _log "Startup recovery yielded to phone — exiting"
        exit 0
    fi

    if [ "$_RECOVERY_MODE" -eq 1 ]; then
        _log "Read-only recovery mode — monitoring only, no task writes"
        while true; do
            sleep "$LOOP_SLEEP"
            if _query_phone_state >/dev/null 2>&1; then
                if _validate_authority; then
                    _log "Authority restored — exiting recovery mode"
                    _RECOVERY_MODE=0
                    break
                fi
            fi
        done
    fi

    trap 'uom_state_lock_release' 0 HUP INT TERM

    while true; do
        if ! net_ok; then
            _log "Offline. Waiting ${LOOP_SLEEP}s..."
            sleep "$LOOP_SLEEP"
            continue
        fi

        uom_heartbeat_write "$AGENT"
        _announce_ip
        _sync_phone_ssh

        _active=$(uom_state_get "active_agent")
        _status=$(uom_state_get "task_status")
        if [ "$_active" = "phone" ] && [ "$_status" = "in_progress" ]; then
            _log "Phone is working. Deferring."
            sleep "$LOOP_SLEEP"
            continue
        fi

        _task_id=$(state_next_task)
        if [ -z "$_task_id" ]; then
            _log "No pending tasks. Idle."
            sleep "$LOOP_SLEEP"
            continue
        fi

        if ! _validate_authority; then
            _log "Authority invalid before task write — pausing"
            sleep "$LOOP_SLEEP"
            continue
        fi

        _task_desc=$(state_task_desc "$_task_id")
        _context=$(state_task_context "$_task_id")

        _log "Starting: $_task_id — $_task_desc"
        state_mark_task "$_task_id" "in_progress"
        state_set "current_task_id" "$_task_id"
        state_set "task_status" "in_progress"
        state_git_sync "start: $_task_id [$AGENT]"

        _out="$(uom_tmpdir)/uom-oc-laptop-$$.txt"
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
