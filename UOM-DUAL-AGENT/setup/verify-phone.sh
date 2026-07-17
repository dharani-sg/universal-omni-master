#!/bin/sh
# verify-phone.sh — verify phone side via reverse tunnel (localhost:18022)
# Run on laptop after phone has: sshd + reverse tunnel open

set -u
REV_HOST="${UOM_REV_HOST:-127.0.0.1}"
REV_PORT="${UOM_REV_PORT:-18022}"
KEY="${UOM_PHONE_KEY:-$HOME/.ssh/id_ed25519_phone}"
KNOWN="$HOME/.ssh/known_hosts_uom"
USER_FILE="$HOME/.uom-termux-user"
PASS=0
FAIL=0

_ok() { printf '  [OK] %s\n' "$*"; PASS=$((PASS+1)); }
_bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
_info() { printf '  [..] %s\n' "$*"; }

printf '=== UOM phone reverse-SSH verification ===\n'
printf 'target %s:%s key=%s\n\n' "$REV_HOST" "$REV_PORT" "$KEY"

# 1. Local reverse port listening
if ss -tln 2>/dev/null | grep -q ":${REV_PORT} "; then
    _ok "reverse port ${REV_PORT} is listening on laptop"
else
    _bad "reverse port ${REV_PORT} NOT listening — phone must run: sh ~/bin/uom-reverse-ssh.sh"
fi

# 2. Discover Termux user
TERMUX_USER=""
if [ -f "$USER_FILE" ]; then
    TERMUX_USER=$(cat "$USER_FILE")
    _ok "cached Termux user: $TERMUX_USER"
fi

if [ -z "$TERMUX_USER" ]; then
    _info "probing banner for user hint..."
    # Try common patterns by failing auth and parsing? Better: try empty and use ssh -v
    # Probe with BatchMode against 'root' just to test TCP+sshd
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile="$KNOWN" -i "$KEY" -p "$REV_PORT" \
        "probe@${REV_HOST}" true 2>&1 | grep -qi 'permission denied\|publickey'; then
        _ok "sshd answers on reverse port (auth challenge works)"
    else
        _bad "no sshd response on ${REV_HOST}:${REV_PORT}"
    fi
fi

# If still unknown, try reading via a forced command attempt with several users
if [ -z "$TERMUX_USER" ]; then
    for cand in u0_a0 u0_a1 u0_a100 u0_a200 u0_a257 u0_a300 u0_a333 u0_a400 u0_a500; do
        if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile="$KNOWN" -i "$KEY" -p "$REV_PORT" \
            "${cand}@${REV_HOST}" 'id -un' 2>/dev/null | grep -q .; then
            TERMUX_USER=$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile="$KNOWN" -i "$KEY" -p "$REV_PORT" \
                "${cand}@${REV_HOST}" 'id -un' 2>/dev/null)
            break
        fi
    done
fi

# Also try: if authorized_keys worked for any user, connect and read
if [ -z "$TERMUX_USER" ] && [ -f "$HOME/.ssh/config" ]; then
    # try without user (will fail) — skip
    true
fi

# 3. Full remote checks if user known
if [ -n "$TERMUX_USER" ]; then
    _info "running remote checks as $TERMUX_USER"
    SSH="ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$KNOWN -i $KEY -p $REV_PORT ${TERMUX_USER}@${REV_HOST}"

    if OUT=$($SSH 'id -un && echo --- && command -v sshd git jq tmux node npm 2>/dev/null; echo ---; test -f ~/.uom-phone-ready && cat ~/.uom-phone-ready; echo ---; test -d ~/src/universal-omni-master && echo repo=yes || echo repo=no; echo ---; command -v opencode >/dev/null && opencode --version || echo opencode=missing; echo ---; pgrep -a sshd 2>/dev/null | head -3' 2>&1); then
        printf '%s\n' "$OUT" | sed 's/^/    /'
        echo "$TERMUX_USER" > "$USER_FILE"
        _ok "remote shell + checks succeeded"
        printf '%s\n' "$OUT" | grep -q 'repo=yes' && _ok "UOM repo present on phone" || _bad "UOM repo missing on phone"
        printf '%s\n' "$OUT" | grep -q 'ready=1' && _ok "phone bootstrap marker present" || _bad "bootstrap marker missing"
        printf '%s\n' "$OUT" | grep -qi 'opencode=missing' && _bad "opencode not installed" || _ok "opencode present (or check output)"
    else
        _bad "SSH as $TERMUX_USER failed: $OUT"
    fi
else
    _info "Termux user unknown — after bootstrap, phone writes ~/.uom-termux-user"
    _info "Or: ssh -p $REV_PORT -i $KEY <termux-user>@$REV_HOST 'id -un' > $USER_FILE"
fi

# 4. Update SSH config Host user
if [ -n "$TERMUX_USER" ]; then
    CFG="$HOME/.ssh/config"
    if grep -q 'Host uom-phone-rev' "$CFG" 2>/dev/null; then
        # replace User line under uom-phone-rev block (simple approach: rewrite host entry)
        _info "updating ~/.ssh/config User for uom-phone-rev → $TERMUX_USER"
        # Use a safe rewrite of the reverse host block
        awk -v u="$TERMUX_USER" '
          BEGIN{inblock=0}
          /^Host uom-phone-rev$/{inblock=1; print; next}
          inblock && /^Host /{inblock=0}
          inblock && /^[[:space:]]*User /{print "    User " u; next}
          {print}
        ' "$CFG" > "${CFG}.tmp" && mv "${CFG}.tmp" "$CFG"
        chmod 600 "$CFG"
        _ok "ssh config updated (Host uom-phone-rev)"
    fi
fi

printf '\n=== summary: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
