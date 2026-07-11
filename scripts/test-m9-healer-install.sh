#!/bin/sh
# scripts/test-m9-healer-install.sh — M9 verification (post-audit).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-50s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else
        printf '  FAIL %-50s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

echo "=== M9 Healer Install Tests ==="

# 1. Explicit asset list — no wildcards (A14 fix).
# Only .sh-parseable assets go through sh -n; declarative files (systemd unit,
# dinit spec) are just verified to exist and be non-empty.
for asset in openrc.initd runit.run runit.log.run s6.run; do
    _p="$ROOT/src/healer/init/$asset"
    if [ -f "$_p" ] && sh -n "$_p" 2>/dev/null; then
        check "syntax: $asset" ok ok
    else
        check "syntax: $asset" ok "fail(missing or bad)"
    fi
done

for decl in systemd.service dinit.service; do
    _p="$ROOT/src/healer/init/$decl"
    [ -s "$_p" ] && check "present: $decl" yes yes || check "present: $decl" yes no
done

sh -n "$ROOT/src/deploy/healer_install.sh" && check "syntax: healer_install.sh" ok ok

# 2. Functional install into a fake target root, per init system
. "$ROOT/src/core/logging.sh" 2>/dev/null
. "$ROOT/src/deploy/healer_install.sh"
_OMNI_ROOT="$ROOT"; export _OMNI_ROOT

for init in systemd openrc runit dinit s6; do
    FAKE="/tmp/omni-m9-test-$$-$init"
    rm -rf "$FAKE"; mkdir -p "$FAKE"
    deploy_install_healer "$FAKE" "$init" >/dev/null 2>&1

    # Common assertions (all inits)
    check "$init: binary copied"     yes "$([ -x "$FAKE/usr/lib/omni-master/bin/omni-healer" ] && echo yes || echo no)"
    check "$init: symlink present"   yes "$([ -L "$FAKE/usr/bin/omni-healer" ] && echo yes || echo no)"
    check "$init: logging.sh copied" yes "$([ -f "$FAKE/usr/lib/omni-master/src/core/logging.sh" ] && echo yes || echo no)"
    check "$init: conf written"      yes "$([ -f "$FAKE/etc/omni-healer.conf" ] && echo yes || echo no)"

    # Per-init unit + enablement assertions
    case "$init" in
        systemd)
            check "systemd: unit file"    yes "$([ -f "$FAKE/usr/lib/systemd/system/omni-healer.service" ] && echo yes || echo no)"
            check "systemd: enable link"  yes "$([ -L "$FAKE/etc/systemd/system/multi-user.target.wants/omni-healer.service" ] && echo yes || echo no)"
            ;;
        openrc)
            check "openrc: init script"   yes "$([ -x "$FAKE/etc/init.d/omni-healer" ] && echo yes || echo no)"
            check "openrc: runlevel link" yes "$([ -L "$FAKE/etc/runlevels/default/omni-healer" ] && echo yes || echo no)"
            ;;
        runit)
            check "runit: run script"     yes "$([ -x "$FAKE/etc/sv/omni-healer/run" ] && echo yes || echo no)"
            check "runit: log/run script" yes "$([ -x "$FAKE/etc/sv/omni-healer/log/run" ] && echo yes || echo no)"
            check "runit: runsvdir link"  yes "$([ -L "$FAKE/etc/runit/runsvdir/default/omni-healer" ] && echo yes || echo no)"
            ;;
        dinit)
            check "dinit: service file"   yes "$([ -f "$FAKE/etc/dinit.d/omni-healer" ] && echo yes || echo no)"
            check "dinit: boot.d link"    yes "$([ -L "$FAKE/etc/dinit.d/boot.d/omni-healer" ] && echo yes || echo no)"
            ;;
        s6)
            check "s6: type file"         yes "$([ -f "$FAKE/etc/s6-rc/source/omni-healer/type" ] && echo yes || echo no)"
            check "s6: run script"        yes "$([ -x "$FAKE/etc/s6-rc/source/omni-healer/run" ] && echo yes || echo no)"
            check "s6: contents.d entry"  yes "$([ -f "$FAKE/etc/s6-rc/source/default/contents.d/omni-healer" ] && echo yes || echo no)"
            ;;
    esac

    rm -rf "$FAKE"
done

# 3. Non-destructive config preservation
FAKE="/tmp/omni-m9-config-$$"
rm -rf "$FAKE"; mkdir -p "$FAKE/etc"
printf 'CUSTOM_MARKER=42\n' > "$FAKE/etc/omni-healer.conf"
deploy_install_healer_files "$FAKE" "$ROOT" >/dev/null 2>&1
grep -q "CUSTOM_MARKER=42" "$FAKE/etc/omni-healer.conf" && \
    check "conf preservation (non-destructive)" yes yes || \
    check "conf preservation (non-destructive)" yes no
rm -rf "$FAKE"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
