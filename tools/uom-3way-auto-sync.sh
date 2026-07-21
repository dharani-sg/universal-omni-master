#!/bin/sh
# Universal Omni-Master: 3-Way Resilient Auto-Sync Daemon
# Syncs Laptop <-> Phone1 (Mi 8) <-> Phone2 (Redmi 13C Host & VM)
# Resilient against power cuts / laptop shutdown.

INTERVAL=${1:-180}
REPO="/home/alpine/src/universal-omni-master"
SSHKEY_PHONE="/home/alpine/.ssh/id_ed25519_phone"
PIDFILE="/home/alpine/src/universal-omni-master/.uom-agent/pids/3way-sync.pid"
LOGFILE="/home/alpine/src/universal-omni-master/.uom-agent/logs/3way-sync.log"
BUNDLE="/tmp/uom-3way-auto.bundle"

PHONE1_HOST="10.155.18.144"
PHONE1_PORT="8022"
PHONE1_USER="u0_a608"
PHONE1_DIR="~/src/universal-omni-master"

PHONE2_HOST="10.155.18.131"
PHONE2_PORT="8022"
PHONE2_USER="u0_a217"
PHONE2_DIR="~/src/universal-omni-master"

echo $$ > "$PIDFILE"

log() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[$ts] $1" | tee -a "$LOGFILE"
}

log "Starting 3-Way Auto-Sync loop (Interval: ${INTERVAL}s)..."

while true; do
  cd "$REPO" || exit 1

  # Stage and commit any uncommitted changes on laptop
  if [ -n "$(git status --porcelain)" ]; then
    log "Dirty working tree detected — committing changes..."
    git add -A
    git commit -m "sync(auto): 3-way resilient sync $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>&1 | tee -a "$LOGFILE" || true
  fi

  # Create bundle
  rm -f "$BUNDLE"
  if git bundle create "$BUNDLE" main 2>/dev/null; then
    # 1. Sync to Phone 1 (Xiaomi Mi 8)
    if scp -i "$SSHKEY_PHONE" -o ConnectTimeout=10 -P "$PHONE1_PORT" "$BUNDLE" "$PHONE1_USER@$PHONE1_HOST:~/uom-auto.bundle" 2>/dev/null; then
      ssh -i "$SSHKEY_PHONE" -o BatchMode=yes -o ConnectTimeout=5 -p "$PHONE1_PORT" "$PHONE1_USER@$PHONE1_HOST" \
        "cd $PHONE1_DIR && git fetch ~/uom-auto.bundle main:refs/heads/main-auto 2>/dev/null && git merge --ff-only main-auto 2>/dev/null" && \
        log "Pushed & merged main to Phone 1 ($PHONE1_HOST)" || log "Phone 1 fetch/merge skipped or dirty"
    else
      log "Phone 1 ($PHONE1_HOST) unreachable"
    fi

    # 2. Sync to Phone 2 Host (Redmi 13C)
    if scp -i "$SSHKEY_PHONE" -o ConnectTimeout=10 -P "$PHONE2_PORT" "$BUNDLE" "$PHONE2_USER@$PHONE2_HOST:~/uom-auto.bundle" 2>/dev/null; then
      ssh -i "$SSHKEY_PHONE" -o BatchMode=yes -o ConnectTimeout=5 -p "$PHONE2_PORT" "$PHONE2_USER@$PHONE2_HOST" \
        "cd $PHONE2_DIR && git fetch ~/uom-auto.bundle main:refs/heads/main-auto 2>/dev/null && git merge --ff-only main-auto 2>/dev/null" && \
        log "Pushed & merged main to Phone 2 Host ($PHONE2_HOST)" || log "Phone 2 host fetch/merge skipped or dirty"

      # 3. Sync to Phone 2 VM (if VM is up)
      ssh -i "$SSHKEY_PHONE" -o BatchMode=yes -o ConnectTimeout=5 -p "$PHONE2_PORT" "$PHONE2_USER@$PHONE2_HOST" \
        'cat ~/uom-auto.bundle | ssh -i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=10 -p 22222 uom@127.0.0.1 "cat > /tmp/uom-auto.bundle && cd ~/src/universal-omni-master && git fetch /tmp/uom-auto.bundle main:refs/heads/main-auto 2>/dev/null && git merge --ff-only main-auto 2>/dev/null" 2>/dev/null' && \
        log "Pushed & merged main to Phone 2 VM (127.0.0.1:22222)" || log "Phone 2 VM offline or skipped"
    else
      log "Phone 2 ($PHONE2_HOST) unreachable"
    fi
  else
    log "ERROR: Failed to create git bundle"
  fi

  sleep "$INTERVAL"
done
