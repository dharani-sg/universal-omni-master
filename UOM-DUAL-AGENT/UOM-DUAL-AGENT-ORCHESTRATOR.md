# UOM Dual-Agent Orchestrator — Complete Setup Guide

> **Target:** HP Pavilion 15-n010tx (Alpine Linux / OpenRC / musl) + Xiaomi Mi 8 (CrDroid Android 15 / Termux)
> **Goal:** opencode loop orchestrator with power-failure fallback, hotspot-switching resilience, GitHub state sync

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       UOM DUAL-AGENT SYSTEM                             │
│                                                                         │
│  [GitHub: universal-omni-master]                                        │
│  .uom-agent/                                                            │
│    state.json   ← active agent, current task, heartbeat timestamps      │
│    laptop.ip    ← laptop IP (written on every network connect)          │
│    phone.ip     ← phone IP (written on every network connect)           │
│    queue.json   ← ordered UOM task queue                               │
│    done.json    ← completed task log                                    │
│                          ▲ git push/pull                                │
│              ┌───────────┴────────────┐                                 │
│              │                        │                                 │
│  [LAPTOP: Alpine Linux]     [PHONE: Termux / Mi 8]                     │
│  uom-orch-laptop.sh         uom-orch-phone.sh                          │
│                                                                         │
│  ┌──────────────────┐       ┌──────────────────────┐                   │
│  │ PRIMARY AGENT    │       │ WATCHDOG + FALLBACK  │                   │
│  │                  │       │                      │                   │
│  │ 1. Pull state    │       │ 1. Pull heartbeat    │                   │
│  │ 2. opencode run  │       │ 2. If > 5min stale:  │                   │
│  │ 3. Commit result │       │    → become PRIMARY  │                   │
│  │ 4. Push state    │       │ 3. opencode run      │                   │
│  │ 5. Heartbeat     │       │ 4. Push result+state │                   │
│  │ 6. Loop          │       │ 5. Watch for laptop  │                   │
│  └──────────────────┘       │    to come back      │                   │
│                             └──────────────────────┘                   │
│                                                                         │
│  NETWORK MODES:                                                         │
│  A) Phone = hotspot  → Laptop finds phone at 192.168.43.1:8022         │
│  B) External WiFi    → Both write IP to GitHub; read to SSH            │
│  C) Laptop powered off → Phone runs independently, commits to GitHub   │
│  D) Reconnect        → Laptop pulls, detects phone work, continues     │
└─────────────────────────────────────────────────────────────────────────┘
```

**Core principle:** GitHub is the communication bus. Neither device controls the other directly — state is committed after every subtask. Power loss at any point = safe. Resume = git pull + continue.

---

## Phase 1 — Phone Setup (Termux on Xiaomi Mi 8 / CrDroid Android 15)

### 1.1 Install Termux correctly

**CRITICAL:** Do NOT install from Google Play Store — that version is frozen. Use F-Droid.

1. On Mi 8, open browser → download **F-Droid** from `https://f-droid.org`
2. Enable "Install from unknown sources" for F-Droid in CrDroid settings
3. In F-Droid, search and install:
   - **Termux** (main app)
   - **Termux:Boot** (auto-start scripts on phone reboot)
   - **Termux:Widget** (optional: home screen shortcuts)

### 1.2 First Termux boot — grant storage and update

```sh
# In Termux:
termux-setup-storage     # grant storage access when prompted
pkg update && pkg upgrade -y
```

### 1.3 Install all required packages

```sh
pkg install -y \
  nodejs-lts \
  git \
  openssh \
  tmux \
  curl \
  wget \
  jq \
  python3 \
  iproute2 \
  nmap
```

### 1.4 Install opencode on phone

Try the direct install script first (checks for ARM64 binary):

```sh
curl -fsSL https://opencode.ai/install | sh
```

If that fails (binary not found for Termux's ARM64 env), use npm:

```sh
npm install -g opencode-ai
```

Verify:

```sh
opencode --version
```

If neither works, use the Bun approach:

```sh
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
bun install -g opencode-ai
```

### 1.5 Configure opencode AI provider (free tier)

```sh
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/config.json << 'EOF'
{
  "provider": "openrouter",
  "model": "google/gemini-2.5-flash",
  "apiKey": "YOUR_OPENROUTER_KEY_HERE"
}
EOF
```

> **Free models via OpenRouter** (as of mid-2026): `google/gemini-2.5-flash`, `meta-llama/llama-3.3-70b-instruct:free`, `deepseek/deepseek-chat:free`. Check `openrouter.ai/models?q=free` for current list.
>
> **Alternative — Gemini direct (most generous free tier):**
> ```sh
> # Use provider "google" with your GEMINI_API_KEY from aistudio.google.com
> ```

### 1.6 Set up SSH server on phone

Termux's SSH runs on **port 8022** (not 22 — Android restricts ports below 1024 without root).

```sh
# Generate host keys
ssh-keygen -A

# Set a password for key-based auth setup
passwd

# Start sshd
sshd

# Verify it's running
ps aux | grep sshd
```

Phone's sshd config is at `~/.ssh/sshd_config`. To harden slightly:

```sh
cat >> ~/.ssh/sshd_config << 'EOF'
PasswordAuthentication no
PubkeyAuthentication yes
EOF
```

### 1.7 Generate phone SSH keypair + GitHub auth

```sh
# Keypair for GitHub
ssh-keygen -t ed25519 -C "dharani-phone-mi8" -f ~/.ssh/id_ed25519_github -N ""

# Print public key to add to GitHub
cat ~/.ssh/id_ed25519_github.pub

# Configure SSH to use this key for GitHub
cat > ~/.ssh/config << 'EOF'
Host github.com
    IdentityFile ~/.ssh/id_ed25519_github
    User git

# Laptop (when connected to same network)
Host uom-laptop
    HostName 192.168.43.100
    Port 22
    User dharani
    IdentityFile ~/.ssh/id_ed25519_laptop
    StrictHostKeyChecking no
    ConnectTimeout 5
EOF
```

Add `~/.ssh/id_ed25519_github.pub` to your GitHub account:
→ GitHub → Settings → SSH and GPG keys → New SSH key

### 1.8 Clone UOM repo on phone

```sh
mkdir -p ~/src
cd ~/src
git clone git@github.com:dharani-sg/universal-omni-master.git
cd universal-omni-master

# Create agent state directory
mkdir -p .uom-agent
git config user.email "dharani.phone@local"
git config user.name "Dharani-Phone-Mi8"
```

### 1.9 Set up tmux layout on phone

Create a startup script for the tmux session:

```sh
cat > ~/bin/uom-session.sh << 'EOF'
#!/bin/sh
# UOM phone tmux session — portrait-optimized for Mi 8 9:16 screen
SESSION="uom"

# Kill any existing session
tmux kill-session -t "$SESSION" 2>/dev/null || true

tmux new-session -d -s "$SESSION" -x 120 -y 40

# Window 0: Phone orchestrator (always running)
tmux rename-window -t "$SESSION:0" "orchestrator"
tmux send-keys -t "$SESSION:0" "cd ~/src/universal-omni-master && sh tools/uom-orch-phone.sh 2>&1 | tee ~/.uom-phone.log" ""

# Window 1: opencode workspace
tmux new-window -t "$SESSION" -n "opencode"
tmux send-keys -t "$SESSION:1" "cd ~/src/universal-omni-master" ""

# Window 2: git status monitor
tmux new-window -t "$SESSION" -n "git"
tmux send-keys -t "$SESSION:2" "cd ~/src/universal-omni-master && watch -n 30 'git log --oneline -5 && echo && cat .uom-agent/state.json'" ""

# Window 3: SSH to laptop (manual use)
tmux new-window -t "$SESSION" -n "laptop-ssh"
tmux send-keys -t "$SESSION:3" "# ssh dharani@$(cat ~/.last-laptop-ip 2>/dev/null || echo 192.168.43.100) -p 22" ""

# Attach to window 0
tmux select-window -t "$SESSION:0"
tmux attach-session -t "$SESSION"
EOF
chmod +x ~/bin/uom-session.sh
mkdir -p ~/bin
```

### 1.10 Auto-start on phone reboot (Termux:Boot)

```sh
mkdir -p ~/.termux/boot

cat > ~/.termux/boot/start-uom.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Auto-start UOM orchestrator on phone reboot
sleep 10   # Let network settle
sshd       # Start SSH server
cd /data/data/com.termux/files/home/src/universal-omni-master
tmux new-session -d -s uom -x 120 -y 40
tmux send-keys -t uom "sh tools/uom-orch-phone.sh 2>&1 | tee ~/.uom-phone.log" ""
EOF
chmod +x ~/.termux/boot/start-uom.sh
```

---

## Phase 2 — Laptop Setup (Alpine Linux / OpenRC)

### 2.1 Install required packages on Alpine

```sh
doas apk add --no-cache \
  openssh \
  git \
  curl \
  jq \
  tmux \
  avahi \
  avahi-tools \
  nss-mdns \
  nmap \
  nodejs \
  npm
```

Enable avahi for mDNS (device discovery without static IPs):

```sh
doas rc-update add avahi-daemon default
doas rc-service avahi-daemon start

# Edit /etc/nsswitch.conf — add mdns4_minimal before dns
doas sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
```

### 2.2 SSH key for phone access from laptop

```sh
# Generate key for laptop→phone SSH
ssh-keygen -t ed25519 -C "dharani-laptop-to-phone" -f ~/.ssh/id_ed25519_phone -N ""

# Print it — you'll paste this into phone's authorized_keys
cat ~/.ssh/id_ed25519_phone.pub
```

On phone (in Termux):

```sh
# Paste the laptop's public key into phone's authorized_keys
echo "paste-laptop-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

On laptop, configure SSH:

```sh
cat >> ~/.ssh/config << 'EOF'

# Phone via Termux (when phone is hotspot)
Host uom-phone-hotspot
    HostName 192.168.43.1
    Port 8022
    User u0_a<YOUR_UID>
    IdentityFile ~/.ssh/id_ed25519_phone
    StrictHostKeyChecking no
    ConnectTimeout 5

# Phone via mDNS (when on same external WiFi)
Host uom-phone-mdns
    HostName mi8.local
    Port 8022
    User u0_a<YOUR_UID>
    IdentityFile ~/.ssh/id_ed25519_phone
    StrictHostKeyChecking no
    ConnectTimeout 5
EOF
```

> **Note:** Replace `u0_a<YOUR_UID>` with your actual Termux user. Find it with `id -un` in Termux.

### 2.3 IP announcement script (runs on network connect)

```sh
cat > /etc/network/if-up.d/uom-announce << 'EOF'
#!/bin/sh
# Announce laptop IP to GitHub state file on network connect
# Triggered by ifup

REPO_DIR="$HOME/src/universal-omni-master"
[ -d "$REPO_DIR/.uom-agent" ] || exit 0

MY_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
[ -z "$MY_IP" ] && exit 0

echo "$MY_IP" > "$REPO_DIR/.uom-agent/laptop.ip"
cd "$REPO_DIR"
git add .uom-agent/laptop.ip
git diff --cached --quiet && exit 0  # no change, skip
git commit -m "heartbeat: laptop IP announce $MY_IP $(date -Iseconds)"
git push origin main 2>/dev/null || true
EOF
doas chmod +x /etc/network/if-up.d/uom-announce
```

Alternatively, add as an OpenRC local script:

```sh
cat > /etc/local.d/uom-announce.start << 'EOF'
#!/bin/sh
sleep 15  # wait for network
/etc/network/if-up.d/uom-announce
EOF
doas chmod +x /etc/local.d/uom-announce.start
doas rc-update add local default
```

---

## Phase 3 — Shared State Protocol

The `.uom-agent/` directory in your repo is the coordination bus.

### 3.1 State file schema

```sh
# .uom-agent/state.json
{
  "schema": 1,
  "active_agent": "laptop",
  "laptop_heartbeat": "2026-07-17T10:00:00Z",
  "phone_heartbeat": "2026-07-17T10:00:30Z",
  "current_task_id": "M28-termux-haptic",
  "current_task_desc": "Implement Termux haptic feedback in omni-tui",
  "task_status": "in_progress",
  "last_commit": "abc1234",
  "session_id": "dharani-20260717-001",
  "takeover_count": 0
}
```

### 3.2 Task queue file

```sh
# .uom-agent/queue.json
[
  {
    "id": "M28-termux-haptic",
    "desc": "Add termux-vibrate haptic feedback to omni-tui portrait mode",
    "context_file": ".uom-agent/context/M28-haptic.md",
    "priority": 1,
    "status": "pending"
  },
  {
    "id": "M28-portrait-reflow",
    "desc": "Implement 9:16 portrait menu reflow in omni-tui for phone SSH",
    "context_file": ".uom-agent/context/M28-portrait.md",
    "priority": 2,
    "status": "pending"
  }
]
```

### 3.3 Create the shared state library (POSIX sh)

```sh
mkdir -p ~/src/universal-omni-master/tools
```

```sh
cat > ~/src/universal-omni-master/tools/uom-orch-state.sh << 'STATEOF'
#!/bin/sh
# tools/uom-orch-state.sh — Shared state functions (POSIX/BusyBox ash safe)
# Source this from both laptop and phone orchestrators
# POSIX-first: zero bashisms, zero eval, zero set --

_STATE_DIR="${OMNI_ROOT:-.}/.uom-agent"
_STATE_FILE="$_STATE_DIR/state.json"
_QUEUE_FILE="$_STATE_DIR/queue.json"
_DONE_FILE="$_STATE_DIR/done.json"
_HEARTBEAT_STALE_SECS=300   # 5 minutes = laptop is dead

state_init() {
    mkdir -p "$_STATE_DIR/context"
    [ -f "$_STATE_FILE" ] || printf '{"schema":1,"active_agent":"none","laptop_heartbeat":"","phone_heartbeat":"","current_task_id":"","task_status":"idle","takeover_count":0}\n' > "$_STATE_FILE"
    [ -f "$_QUEUE_FILE" ] || printf '[]\n' > "$_QUEUE_FILE"
    [ -f "$_DONE_FILE"  ] || printf '[]\n' > "$_DONE_FILE"
}

state_get() {
    # state_get <field>
    jq -r ".$1 // empty" "$_STATE_FILE" 2>/dev/null
}

state_set() {
    # state_set <field> <value>
    _field="$1"; _val="$2"
    _tmp="${_STATE_FILE}.tmp"
    jq ".$_field = \"$_val\"" "$_STATE_FILE" > "$_tmp" && mv "$_tmp" "$_STATE_FILE"
}

state_heartbeat() {
    # state_heartbeat <agent: laptop|phone>
    _agent="$1"
    _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    state_set "${_agent}_heartbeat" "$_now"
    state_set "active_agent" "$_agent"
}

state_laptop_stale() {
    # Returns 0 (true) if laptop heartbeat is older than threshold
    _ts=$(state_get "laptop_heartbeat")
    [ -z "$_ts" ] && return 0   # never set = stale

    # Convert ISO timestamp to epoch seconds (POSIX-compatible via date)
    _epoch_now=$(date -u +%s 2>/dev/null)
    # BusyBox date -d for parsing; fall back to python3 if unavailable
    _epoch_hb=$(date -u -d "$_ts" +%s 2>/dev/null) || \
        _epoch_hb=$(python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$_ts').timestamp()))" 2>/dev/null) || \
        _epoch_hb=0

    _diff=$(( _epoch_now - _epoch_hb ))
    [ "$_diff" -gt "$_HEARTBEAT_STALE_SECS" ]
}

state_next_task() {
    # Returns first pending task ID, or empty string
    jq -r '[.[] | select(.status=="pending")] | first | .id // empty' "$_QUEUE_FILE" 2>/dev/null
}

state_task_desc() {
    # state_task_desc <task_id>
    jq -r --arg id "$1" '.[] | select(.id==$id) | .desc // empty' "$_QUEUE_FILE" 2>/dev/null
}

state_task_context() {
    # state_task_context <task_id> — reads context md file if present
    _ctx_file=$(jq -r --arg id "$1" '.[] | select(.id==$id) | .context_file // empty' "$_QUEUE_FILE" 2>/dev/null)
    [ -n "$_ctx_file" ] && [ -f "${OMNI_ROOT:-.}/$_ctx_file" ] && cat "${OMNI_ROOT:-.}/$_ctx_file"
}

state_mark_task() {
    # state_mark_task <task_id> <status: in_progress|done|failed>
    _id="$1"; _status="$2"
    _tmp="${_QUEUE_FILE}.tmp"
    jq --arg id "$_id" --arg st "$_status" \
       'map(if .id==$id then .status=$st else . end)' \
       "$_QUEUE_FILE" > "$_tmp" && mv "$_tmp" "$_QUEUE_FILE"

    if [ "$_status" = "done" ]; then
        _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
        _agent=$(state_get "active_agent")
        _tmp2="${_DONE_FILE}.tmp"
        jq --arg id "$_id" --arg t "$_now" --arg a "$_agent" \
           '. + [{"id":$id,"completed":$t,"by":$a}]' \
           "$_DONE_FILE" > "$_tmp2" && mv "$_tmp2" "$_DONE_FILE"
    fi
}

state_git_sync() {
    # state_git_sync <commit_msg> — add state files, commit, push
    _msg="$1"
    cd "${OMNI_ROOT:-.}" || return 1
    git add .uom-agent/ 2>/dev/null
    git diff --cached --quiet && return 0   # nothing to commit
    git commit -m "$_msg" || return 1
    git push origin main 2>/dev/null || true  # push; don't fail if offline
}

state_git_pull() {
    cd "${OMNI_ROOT:-.}" || return 1
    git pull --rebase origin main 2>/dev/null || true
}
STATEOF
```

---

## Phase 4 — Orchestrator Scripts

### 4.1 Laptop orchestrator

```sh
cat > ~/src/universal-omni-master/tools/uom-orch-laptop.sh << 'LAPTOPORCHEOF'
#!/bin/sh
# tools/uom-orch-laptop.sh — Laptop-side UOM loop orchestrator
# HP Pavilion 15 / Alpine Linux / POSIX sh
# Run in tmux: tmux new -s orch 'sh tools/uom-orch-laptop.sh'

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
. "$OMNI_ROOT/tools/uom-orch-state.sh"

AGENT="laptop"
LOOP_SLEEP=60          # seconds between loop ticks
OPENCODE_TIMEOUT=1800  # 30 min max per task

_log() { printf '[%s] [LAPTOP] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
_die() { _log "FATAL: $*"; exit 1; }

# ── Network connectivity check ────────────────────────────────────────────
_net_ok() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 3 github.com >/dev/null 2>&1
}

# ── Phone IP discovery ────────────────────────────────────────────────────
_phone_ip() {
    # Try 1: phone is our hotspot → fixed gateway IP
    _gw=$(ip route | awk '/^default/{print $3; exit}')
    if [ "$_gw" = "192.168.43.1" ]; then
        echo "192.168.43.1"; return 0
    fi
    # Try 2: read from GitHub state file
    _ip_file="$OMNI_ROOT/.uom-agent/phone.ip"
    [ -f "$_ip_file" ] && _ip=$(cat "$_ip_file") && [ -n "$_ip" ] && echo "$_ip" && return 0
    # Try 3: mDNS
    avahi-resolve -n mi8.local 2>/dev/null | awk '{print $2}' | head -1
}

# ── Announce own IP ───────────────────────────────────────────────────────
_announce_ip() {
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/laptop.ip"
}

# ── Run opencode on a task ────────────────────────────────────────────────
_run_opencode() {
    _task_id="$1"
    _task_desc="$2"
    _context="$3"

    _prompt="You are working on the Universal Omni-Master (UOM) project.
Task ID: $_task_id
Task: $_task_desc

Project context:
- POSIX sh only. Zero bashisms. Zero eval. Zero set --. BusyBox ash-safe.
- Mutation guard: exit 126 when OMNI_SYSROOT set.
- Reference OS: Alpine Linux 3.x (musl/OpenRC). Secondary: Void Linux (glibc/runit).
- Hardware: HP Pavilion 15-n010tx (i3-3217U, AMD GCN 1.0, Intel HD 4000, 3.72GB RAM, SATA CRC baseline 5360)
- All files pass sh -n syntax check before commit.
- No comments in code unless explicitly needed.

${_context}

Implement the task. Show file paths and complete file contents for any modified files."

    _log "Running opencode for task: $_task_id"
    # Non-interactive mode: pipe prompt to opencode
    # Adjust flag to match your installed opencode version:
    #   Modern: opencode --message "..."
    #   Pipe:   printf '%s\n' "..." | opencode --headless
    #   Run:    opencode run "..."
    printf '%s\n' "$_prompt" | timeout "$OPENCODE_TIMEOUT" opencode 2>&1
    return $?
}

# ── Main loop ─────────────────────────────────────────────────────────────
main() {
    _log "UOM Laptop Orchestrator starting. OMNI_ROOT=$OMNI_ROOT"
    state_init
    cd "$OMNI_ROOT" || _die "Cannot cd to OMNI_ROOT"

    while true; do
        # ─── 1. Network check
        if ! _net_ok; then
            _log "No network. Waiting $LOOP_SLEEP s..."
            sleep "$LOOP_SLEEP"
            continue
        fi

        # ─── 2. Pull latest state
        state_git_pull
        _announce_ip

        # ─── 3. Heartbeat — declare we are alive
        state_heartbeat "$AGENT"

        # ─── 4. Check if phone is already working a task we should defer to
        _current_active=$(state_get "active_agent")
        _task_status=$(state_get "task_status")
        if [ "$_current_active" = "phone" ] && [ "$_task_status" = "in_progress" ]; then
            _log "Phone is active and working. Waiting for it to finish..."
            state_git_sync "heartbeat: laptop alive, deferring to phone $(date -Iseconds)"
            sleep "$LOOP_SLEEP"
            continue
        fi

        # ─── 5. Get next task
        _task_id=$(state_next_task)
        if [ -z "$_task_id" ]; then
            _log "No pending tasks in queue. Idle."
            state_git_sync "heartbeat: laptop idle $(date -Iseconds)"
            sleep "$LOOP_SLEEP"
            continue
        fi

        _task_desc=$(state_task_desc "$_task_id")
        _context=$(state_task_context "$_task_id")

        _log "Starting task: $_task_id — $_task_desc"
        state_mark_task "$_task_id" "in_progress"
        state_set "current_task_id" "$_task_id"
        state_set "task_status" "in_progress"
        state_git_sync "start: task $_task_id [$AGENT]"

        # ─── 6. Run opencode
        _output_file="${TMPDIR:-/tmp}/uom-opencode-$$.txt"
        if _run_opencode "$_task_id" "$_task_desc" "$_context" > "$_output_file" 2>&1; then
            _log "opencode completed task: $_task_id"

            # Save output as context for next session
            cp "$_output_file" "$OMNI_ROOT/.uom-agent/context/${_task_id}-output.md"

            state_mark_task "$_task_id" "done"
            state_set "task_status" "done"
            state_git_sync "done: task $_task_id [$AGENT]"
        else
            _rc=$?
            _log "opencode FAILED for task: $_task_id (exit $rc)"
            cp "$_output_file" "$OMNI_ROOT/.uom-agent/context/${_task_id}-error.md" 2>/dev/null || true
            state_mark_task "$_task_id" "failed"
            state_set "task_status" "failed"
            state_git_sync "failed: task $_task_id [$AGENT] rc=$_rc"
        fi

        rm -f "$_output_file"
        sleep 5   # brief pause before next task
    done
}

main "$@"
LAPTOPORCHEOF
chmod +x ~/src/universal-omni-master/tools/uom-orch-laptop.sh
```

### 4.2 Phone orchestrator

Save this to phone at `~/src/universal-omni-master/tools/uom-orch-phone.sh`:

```sh
#!/bin/sh
# tools/uom-orch-phone.sh — Phone-side UOM orchestrator + watchdog
# Xiaomi Mi 8 / Termux / POSIX sh / BusyBox ash safe
# Run in tmux window 0 automatically via ~/.termux/boot/start-uom.sh

set -u
export OMNI_ROOT="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
. "$OMNI_ROOT/tools/uom-orch-state.sh"

AGENT="phone"
LOOP_SLEEP=60
WATCHDOG_SLEEP=120     # Check laptop every 2 min
OPENCODE_TIMEOUT=2400  # 40 min (phone is slower)
TAKEOVER_GRACE=300     # Wait 5 min of stale heartbeat before takeover

_log() { printf '[%s] [PHONE] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

_net_ok() {
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 5 github.com >/dev/null 2>&1
}

_laptop_reachable() {
    _laptop_ip=$(cat "$OMNI_ROOT/.uom-agent/laptop.ip" 2>/dev/null)
    [ -z "$_laptop_ip" ] && return 1
    ping -c 1 -W 3 "$_laptop_ip" >/dev/null 2>&1 || \
    ssh -o ConnectTimeout=3 -o BatchMode=yes \
        -i ~/.ssh/id_ed25519_laptop \
        "dharani@$_laptop_ip" echo ok >/dev/null 2>&1
}

_announce_phone_ip() {
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    [ -z "$_my_ip" ] && return
    echo "$_my_ip" > "$OMNI_ROOT/.uom-agent/phone.ip"
}

_run_opencode() {
    _task_id="$1"; _task_desc="$2"; _context="$3"

    _prompt="You are working on the Universal Omni-Master (UOM) project.
Task ID: $_task_id
Task: $_task_desc

CONSTRAINTS (immutable):
- POSIX sh only. Zero bashisms. Zero eval. Zero set --. BusyBox ash-safe.
- Mutation guard: exit 126 when OMNI_SYSROOT set.
- Reference OS: Alpine Linux 3.x (musl/OpenRC).
- All output must pass: sh -n <file>

This task was picked up by the PHONE AGENT (Xiaomi Mi 8 / Termux) as FALLBACK
because the laptop (HP Pavilion 15) lost power or connectivity.

${_context}

Implement the task. Show complete file paths and contents."

    _log "Running opencode (phone fallback) for: $_task_id"
    printf '%s\n' "$_prompt" | timeout "$OPENCODE_TIMEOUT" opencode 2>&1
    return $?
}

_handback_to_laptop() {
    # Called when laptop comes back online while phone is working
    _log "Laptop is back online. Finishing current task then handing back."
    # Do NOT abort mid-task; let it finish, push state, then become watchdog
    state_set "task_status" "phone_handback_pending"
    state_git_sync "handback: laptop returned, phone finishing task"
}

main() {
    _log "UOM Phone Watchdog/Orchestrator starting. OMNI_ROOT=$OMNI_ROOT"
    state_init
    cd "$OMNI_ROOT" || exit 1

    _mode="watchdog"  # start as watchdog; escalate to active if laptop dies

    while true; do
        if ! _net_ok; then
            _log "No network on phone. Waiting..."
            sleep "$WATCHDOG_SLEEP"
            continue
        fi

        # Pull latest state
        state_git_pull
        _announce_phone_ip

        # Update phone heartbeat
        state_heartbeat_phone() {
            _now=$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
            state_set "phone_heartbeat" "$_now"
        }
        state_heartbeat_phone

        _current_active=$(state_get "active_agent")
        _task_status=$(state_get "task_status")

        # ─── WATCHDOG MODE: check if we need to take over ─────────────────
        if [ "$_mode" = "watchdog" ]; then
            if state_laptop_stale; then
                _log "Laptop heartbeat STALE. Initiating takeover after ${TAKEOVER_GRACE}s grace..."
                sleep "$TAKEOVER_GRACE"

                # Re-check after grace period
                state_git_pull
                if state_laptop_stale; then
                    _log "TAKEOVER: laptop confirmed offline. Phone becoming PRIMARY."
                    _mode="active"
                    _count=$(state_get "takeover_count")
                    _count=$(( ${_count:-0} + 1 ))
                    state_set "takeover_count" "$_count"
                    state_git_sync "takeover: phone $AGENT assuming primary (count=$_count)"
                else
                    _log "Laptop came back during grace. Staying watchdog."
                fi
            else
                _log "Watchdog: laptop OK. Sleeping ${WATCHDOG_SLEEP}s."
                state_git_sync "heartbeat: phone watchdog $(date -Iseconds)"
                sleep "$WATCHDOG_SLEEP"
                continue
            fi
        fi

        # ─── ACTIVE MODE: phone is primary ────────────────────────────────
        if [ "$_mode" = "active" ]; then
            # Check if laptop came back while we're running
            if ! state_laptop_stale && _laptop_reachable; then
                _log "Laptop is BACK. Switching to handback mode."
                _mode="handback"
            fi

            _task_id=$(state_next_task)
            if [ -z "$_task_id" ]; then
                _log "No pending tasks. Phone idle."
                sleep "$LOOP_SLEEP"
                continue
            fi

            _task_desc=$(state_task_desc "$_task_id")
            _context=$(state_task_context "$_task_id")

            _log "Phone taking task: $_task_id"
            state_mark_task "$_task_id" "in_progress"
            state_set "current_task_id" "$_task_id"
            state_set "task_status" "in_progress"
            state_set "active_agent" "$AGENT"
            state_git_sync "start: task $_task_id [$AGENT phone-fallback]"

            _out="${TMPDIR:-/tmp}/uom-phone-$$.txt"
            if _run_opencode "$_task_id" "$_task_desc" "$_context" > "$_out" 2>&1; then
                _log "Phone completed task: $_task_id"
                cp "$_out" "$OMNI_ROOT/.uom-agent/context/${_task_id}-output.md"
                state_mark_task "$_task_id" "done"
                state_set "task_status" "done"
                state_git_sync "done: task $_task_id [$AGENT phone-fallback]"
            else
                _rc=$?
                _log "Phone FAILED task: $_task_id (exit $_rc)"
                state_mark_task "$_task_id" "failed"
                state_set "task_status" "failed"
                state_git_sync "failed: task $_task_id [$AGENT] rc=$_rc"
            fi
            rm -f "$_out"
        fi

        # ─── HANDBACK MODE: laptop came back, return control ──────────────
        if [ "$_mode" = "handback" ]; then
            _log "Handback: waiting for laptop to announce itself..."
            state_git_pull
            if ! state_laptop_stale; then
                _log "Laptop confirmed via heartbeat. Phone returning to WATCHDOG."
                state_set "active_agent" "laptop"
                state_git_sync "handback: phone returning control to laptop"
                _mode="watchdog"
            else
                _log "Laptop still stale. Staying active."
                _mode="active"
            fi
            sleep "$LOOP_SLEEP"
        fi

    done
}

main "$@"
```

---

## Phase 5 — Power Failure Recovery Flow

```
POWER LOSS on laptop:
  T=0   Laptop loses power. sshd dies. Last heartbeat: T-N seconds.
  T=5m  Phone detects stale heartbeat (laptop_heartbeat + 300s < now).
  T=10m Phone waits TAKEOVER_GRACE=300s, re-checks → confirms stale.
  T=10m Phone escalates to _mode=active. Pulls latest state.json.
  T=10m Phone picks up current_task_id (or next pending task).
  T=10m Phone runs opencode, commits result to GitHub.
  T+Xm  Laptop powers back on (AC power restored).
  T+Xm  Laptop's OpenRC local.d/uom-announce.start fires → announces IP.
  T+Xm  Laptop pulls state → sees phone worked tasks → continues from there.
  T+Xm  Laptop's heartbeat updates. Phone detects, drops back to watchdog.
```

### What the laptop does on recovery boot:

```sh
# Alpine OpenRC: /etc/local.d/uom-resume.start
#!/bin/sh
sleep 20    # let network fully settle
cd /home/dharani/src/universal-omni-master
git pull --rebase origin main
# Check if phone worked something while we were off
_active=$(jq -r '.active_agent' .uom-agent/state.json)
if [ "$_active" = "phone" ]; then
    logger "UOM: phone worked while laptop was offline. Resuming."
fi
# Announce our IP and start orchestrator in background
sh tools/uom-orch-laptop.sh >> /var/log/uom-laptop.log 2>&1 &
```

---

## Phase 6 — Network / Hotspot Switching

### Scenario A: Phone is your hotspot (most common)

```
Phone IP as gateway: 192.168.43.1  ← ALWAYS FIXED when phone is hotspot
Laptop IP: 192.168.43.x            ← DHCP from phone
```

Laptop can always SSH to phone at `192.168.43.1:8022`. No discovery needed.

```sh
# Quick test from laptop
ssh -p 8022 -i ~/.ssh/id_ed25519_phone u0_aXXX@192.168.43.1 echo "phone connected"
```

### Scenario B: Switch to mom/dad WiFi mid-session

```sh
# Automatic: when laptop connects to new WiFi, it runs /etc/network/if-up.d/uom-announce
# This writes new IP to .uom-agent/laptop.ip and pushes to GitHub.
# Phone reads the new IP on next state_git_pull.
# No manual steps needed.
```

The network detect script handles it:

```sh
cat > ~/src/universal-omni-master/tools/uom-net-detect.sh << 'EOF'
#!/bin/sh
# Detect current network mode and set connection targets
# Returns: hotspot | external | offline

_gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
_my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')

if [ -z "$_gw" ] || [ -z "$_my_ip" ]; then
    echo "offline"; exit 0
fi

if [ "$_gw" = "192.168.43.1" ]; then
    # Phone is our hotspot
    echo "hotspot"
    printf 'PHONE_IP=192.168.43.1\nLAPTOP_IP=%s\n' "$_my_ip"
else
    # External WiFi (mom/dad/etc)
    echo "external"
    printf 'LAPTOP_IP=%s\nGATEWAY=%s\n' "$_my_ip" "$_gw"
fi
EOF
chmod +x ~/src/universal-omni-master/tools/uom-net-detect.sh
```

### Scenario C: Reconnect after power loss on different hotspot

Both devices:
1. Boot/reconnect → write their IP to `.uom-agent/laptop.ip` or `phone.ip`
2. Commit + push to GitHub
3. Other device pulls → discovers new IP
4. SSH works again automatically

No manual steps. The IP files in GitHub are the discovery mechanism.

---

## Phase 7 — GitHub Sync Rate Limiting

Phone hotspot data is precious. The orchestrator is designed to be frugal:

- **Heartbeat commits**: every 5 minutes (watchdog mode), only when state changes
- **Task commits**: only on task start / done / fail (not mid-task)
- **git push**: uses `|| true` — if offline, next loop retries
- **git pull**: lightweight fetch, not full clone

To further reduce data usage, shallow clone the repo on phone:

```sh
# On phone: shallow clone (less data)
git clone --depth=50 git@github.com:dharani-sg/universal-omni-master.git
cd universal-omni-master
git config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
```

And limit git history on state files:

```sh
# .uom-agent/.gitattributes
# Keep state files tracked but don't accumulate large history
* -delta
```

---

## Phase 8 — Running the Full System

### On laptop (Alpine Linux):

```sh
# One-time: add .uom-agent to .gitignore exceptions
echo '!.uom-agent/' >> .gitignore
echo '!.uom-agent/**' >> .gitignore

# Start orchestrator in a dedicated tmux window
tmux new-session -d -s uom -n orch
tmux send-keys -t uom:orch \
  "export OMNI_ROOT=$HOME/src/universal-omni-master && sh tools/uom-orch-laptop.sh 2>&1 | tee /tmp/uom-laptop.log" ""

# Watch log
tmux new-window -t uom -n log
tmux send-keys -t uom:log "tail -f /tmp/uom-laptop.log" ""

# Attach
tmux attach -t uom
```

### On phone (Termux):

```sh
sh ~/bin/uom-session.sh   # starts the full tmux session
# Window 0 runs uom-orch-phone.sh automatically
```

### Adding tasks to the queue:

```sh
# From either device:
cd ~/src/universal-omni-master

# Edit queue manually
vi .uom-agent/queue.json

# Or use jq to append:
TASK_ID="M28-termux-notifications"
TASK_DESC="Implement native Termux push notifications in omni-tui for deployment status"

jq --arg id "$TASK_ID" --arg desc "$TASK_DESC" \
   '. + [{"id":$id,"desc":$desc,"context_file":".uom-agent/context/'+$TASK_ID+'.md","priority":3,"status":"pending"}]' \
   .uom-agent/queue.json > .uom-agent/queue.json.tmp && \
   mv .uom-agent/queue.json.tmp .uom-agent/queue.json

# Optional: write context file for the task
cat > .uom-agent/context/${TASK_ID}.md << 'CTXEOF'
## Context for M28 Termux Notifications

omni-tui currently only prints status to stdout. We need to add:
1. termux-notification for deployment start/finish/failure events
2. termux-vibrate on critical failures
3. Graceful degradation: if not in Termux, silently skip

Relevant file: src/tui/dashboard.sh
CTXEOF

git add .uom-agent/
git commit -m "queue: add task $TASK_ID"
git push
```

---

## Phase 9 — opencode Non-Interactive Mode Reference

The exact flag depends on your installed opencode version. Check with `opencode --help` after install.

```sh
# Method A — pipe via stdin (works on most versions)
printf '%s\n' "$prompt" | opencode

# Method B — --message flag (newer versions)
opencode --message "$prompt"

# Method C — run subcommand (if available)
opencode run "$prompt"

# Method D — heredoc approach (BusyBox safe)
opencode << PROMPTEOF
$prompt
PROMPTEOF

# Timeout wrapper (always use this in orchestrator)
printf '%s\n' "$prompt" | timeout 1800 opencode
```

If opencode always opens TUI and ignores stdin, use `expect` or `tmux send-keys`:

```sh
# tmux-based automation (last resort for TUI-only versions)
tmux new-window -t uom -n "oc-$_task_id"
tmux send-keys -t "uom:oc-$_task_id" "opencode" ""
sleep 3
tmux send-keys -t "uom:oc-$_task_id" "$_task_desc" ""
# ... capture output via tmux capture-pane
```

---

## Phase 10 — Troubleshooting

### Phone can't SSH to GitHub

```sh
# Check SSH agent
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519_github
ssh -T git@github.com   # should say "Hi dharani-sg!"
```

### Laptop and phone get merge conflicts on state.json

```sh
# state.json uses last-write-wins; resolve by taking phone's version if laptop was offline
cd ~/src/universal-omni-master
git checkout --theirs .uom-agent/state.json
git add .uom-agent/state.json
git commit -m "resolve: took phone state after laptop recovery"
```

### opencode not found on phone

```sh
# Check where npm installed it
npm bin -g   # → /data/data/com.termux/files/usr/bin or similar
export PATH="$PATH:$(npm bin -g)"
echo 'export PATH="$PATH:'"$(npm bin -g)"'"' >> ~/.bashrc
```

### Heartbeat showing stale even though laptop is on

```sh
# Manual heartbeat reset from laptop
cd ~/src/universal-omni-master
jq '.laptop_heartbeat = "'$(date -Iseconds)'"' .uom-agent/state.json > /tmp/s.json
mv /tmp/s.json .uom-agent/state.json
git add .uom-agent/state.json
git commit -m "manual: reset laptop heartbeat"
git push
```

### SSH to phone fails (port 8022)

```sh
# On phone, check sshd is running
ps aux | grep sshd
# Restart if needed
pkill sshd; sshd

# Check Termux user ID for SSH config
id -un    # e.g., u0_a257
```

### Data saving on phone hotspot

```sh
# Reduce git push frequency — edit LOOP_SLEEP in phone orchestrator
# Default: 60s checks, 120s watchdog sleeps
# For data saving: increase to 300s checks, 600s watchdog
# Edit in tools/uom-orch-phone.sh:
LOOP_SLEEP=300
WATCHDOG_SLEEP=600
```

---

## Quick Reference

| Situation | What happens | Action needed |
|---|---|---|
| Laptop AC power cut | Phone detects stale HB at 5min → takeover at 10min | None — auto |
| Power restored | Laptop pulls phone's work, continues | None — auto |
| Switch from phone hotspot to mom/dad WiFi | laptop.ip updates in GitHub | None — auto |
| Switch back to phone hotspot | Laptop reconnects, uom-announce fires | None — auto |
| Phone reboots | Termux:Boot auto-starts uom-orch-phone.sh | None — auto |
| Laptop reboots | local.d/uom-resume.start fires | None — auto |
| Both offline simultaneously | Each works on last known task independently | Manual merge after reconnect |
| queue.json is empty | Both agents go idle, log "No pending tasks" | Add tasks to queue |
| opencode API rate limit | Task marked failed, retried next loop | Check provider quota |

