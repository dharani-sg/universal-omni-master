#!/bin/sh
# security/install-hooks.sh — Install git pre-commit hooks for UOM
# Blocks accidental secret commits, enforces coding standards

set -u
UOM_DIR="${HOME}/src/universal-omni-master"
HOOK="${UOM_DIR}/.git/hooks/pre-commit"

_log() { printf '[install-hooks] %s\n' "$*"; }

mkdir -p "$(dirname "${HOOK}")"

cat > "${HOOK}" << 'HOOK'
#!/bin/sh
# Pre-commit hook — block secrets + enforce standards

PATTERNS="sk-ant-|ANTHROPIC_API_KEY=|OPENAI_API_KEY=|ssh-rsa AAAA|BEGIN PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY"

STAGED=$(git diff --cached --name-only)
if [ -n "${STAGED}" ]; then
    if echo "${STAGED}" | xargs grep -lE "${PATTERNS}" 2>/dev/null | grep -v -q '^security/install-hooks.sh$'; then
        echo "ERROR: Staged files appear to contain secrets. Aborting commit."
        echo "Fix: remove secrets, add to .gitignore, or use ~/.config/uom/secrets.env"
        exit 1
    fi
fi

# Check for shellcheck (non-blocking warning)
FILES=$(echo "${STAGED}" | grep -E '\.sh$' || true)
for f in ${FILES}; do
    if [ -f "${f}" ]; then
        sh -n "${f}" 2>/dev/null || {
            echo "WARNING: ${f} has shell syntax errors — fix before commit"
        }
    fi
done
HOOK

chmod +x "${HOOK}"
_log "Pre-commit hook installed at ${HOOK}"
_log "Hook will:"
_log "  - Block staged files containing known secret patterns"
_log "  - Warn on shell syntax errors in .sh files"
