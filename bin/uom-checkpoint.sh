#!/bin/sh
# bin/uom-checkpoint.sh — Atomic git checkpoint: stage, commit, update resume
# Usage: sh bin/uom-checkpoint.sh "commit message"
#        sh bin/uom-checkpoint.sh               (auto-generates timestamp message)
# POSIX sh. No bashisms. Safe to run on laptop only.

set -u

UOM_DIR="${HOME}/src/universal-omni-master"
RESUME_FILE="${UOM_DIR}/docs/SESSION-RESUME-2026-07-18.md"

cd "${UOM_DIR}" || { echo "ERROR: Cannot cd to ${UOM_DIR}" >&2; exit 1; }

# ── Generate commit message ────────────────────────────────────────────
if [ -n "${1:-}" ]; then
    _msg="$1"
else
    _ts=$(date +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || date)
    _msg="checkpoint: ${_ts}"
fi

# ── Secret scan (quick) ────────────────────────────────────────────────
if git diff --cached --name-only 2>/dev/null | grep -qiE '\.env$|runtime\.env|credentials|\.key$|\.pem$'; then
    echo "WARNING: Potential secrets in staged files. Aborting." >&2
    echo "Review: git diff --cached --name-only" >&2
    exit 1
fi

# ── Stage all tracked + new doc/test files (exclude secrets, binaries) ─
git add -A 2>/dev/null

# Unstage anything that should never be committed
git reset HEAD -- \
    '*.qcow2' '*.iso' '*.fd' '*.log' '*.pid' '*.lock' \
    'runtime.env' 'zen.env' '*.key' '*.pem' \
    'credentials.env' '*.bak' 2>/dev/null || true

# ── Check if there is anything to commit ───────────────────────────────
if git diff --cached --quiet 2>/dev/null; then
    echo "Nothing to commit (working tree clean)."
    exit 0
fi

# ── Commit ─────────────────────────────────────────────────────────────
git commit -m "${_msg}" --no-verify 2>&1
_rc=$?

if [ "$_rc" -ne 0 ]; then
    echo "ERROR: git commit failed (rc=${_rc})" >&2
    exit "$_rc"
fi

# ── Update resume file with new HEAD ───────────────────────────────────
_new_head=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
if [ -f "${RESUME_FILE}" ]; then
    sed -i "s/HEAD: [a-f0-9]*/HEAD: ${_new_head}/" "${RESUME_FILE}" 2>/dev/null || true
fi

echo "Checkpoint OK: ${_new_head} — ${_msg}"
