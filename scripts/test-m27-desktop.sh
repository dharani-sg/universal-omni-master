#!/bin/sh
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
PASS=0
FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

printf '%s\n' '=== M27 Desktop Profile Engine Tests ==='

for _f in "$ROOT/src/desktop/common.sh" \
          "$ROOT/src/desktop/profiles/"*.sh \
          "$ROOT/bin/omni-desktop"
do
    if sh -n "$_f"; then
        check "syntax: ${_f##*/}" 0 0
    else
        check "syntax: ${_f##*/}" 0 1
    fi
done

. "$ROOT/src/deploy/chroot.sh"
. "$ROOT/src/deploy/configure.sh"
for _f in "$ROOT/src/desktop/profiles/"*.sh; do
    . "$_f"
done
. "$ROOT/src/desktop/common.sh"

WORK="${TMPDIR:-/tmp}/omni-m27-$$"
FAKE="$WORK/root"
mkdir -p "$FAKE/etc" "$FAKE/usr/bin" \
    "$FAKE/usr/share/wayland-sessions" "$FAKE/var/log"

cat > "$FAKE/etc/os-release" << 'OSR'
ID=alpine
OSR

check "detect distro alpine" alpine "$(desktop_detect_distro "$FAKE")"
check "profile niri kind" wayland "$(desktop_profile_query niri kind)"
check "profile quickshell kind" addon "$(desktop_profile_query quickshell kind)"
check "profile hyde external" external "$(desktop_profile_query hyde kind)"

desktop_pkg_available() {
    case "$3" in
        unavailable-package) return 1 ;;
        *) return 0 ;;
    esac
}

_plan=$(desktop_plan_profile niri "$FAKE" alpine 0)
case "$_plan" in
    *required.available=niri*)
        check "niri plan has required package" yes yes ;;
    *)
        check "niri plan has required package" yes no ;;
esac

_rc=0
desktop_plan_profile mango "$FAKE" alpine 0 >/dev/null 2>&1 || _rc=$?
check "mango requires experimental opt-in" 3 "$_rc"

_rc=0
desktop_plan_profile hyde "$FAKE" alpine 0 >/dev/null 2>&1 || _rc=$?
check "HyDE remains external/manual" 3 "$_rc"

AUDIT="$WORK/audit.ndjson"
i=1
while [ "$i" -le 9 ]; do
    printf '{"event":"desktop_install_result","distro":"alpine","profile":"niri","status":"success","packages":"wireplumber brightnessctl"}\n' >> "$AUDIT"
    i=$((i + 1))
done
printf '{"event":"desktop_install_result","distro":"alpine","profile":"niri","status":"failed","packages":"brightnessctl"}\n' >> "$AUDIT"

check "Laplace package recommendation = 83" 83 \
    "$(desktop_telemetry_percent alpine niri wireplumber "$AUDIT")"
check "Laplace success score = 83" 83 \
    "$(desktop_success_percent alpine niri "$AUDIT")"
check "empty telemetry prior = 50" 50 \
    "$(desktop_success_percent alpine sway "$AUDIT")"

touch "$FAKE/usr/bin/niri"
chmod 755 "$FAKE/usr/bin/niri"
touch "$FAKE/usr/share/wayland-sessions/niri.desktop"
touch "$FAKE/usr/bin/pipewire" "$FAKE/usr/bin/wireplumber"
chmod 755 "$FAKE/usr/bin/pipewire" "$FAKE/usr/bin/wireplumber"

_rc=0
desktop_verify_static niri "$FAKE" >/dev/null 2>&1 || _rc=$?
check "static verification passes with binary/session" 0 "$_rc"

_rc=0
OMNI_SYSROOT=/tmp/fx desktop_mark_firstboot_pending \
    "$FAKE" niri testuser >/dev/null 2>&1 || _rc=$?
check "firstboot marker mutation guard" 126 "$_rc"

_rc=0
"$ROOT/bin/omni-desktop" help >/dev/null 2>&1 || _rc=$?
check "CLI help exits zero" 0 "$_rc"

_rc=0
"$ROOT/bin/omni-desktop" bogus >/dev/null 2>&1 || _rc=$?
check "CLI unknown exits two" 2 "$_rc"

rm -rf "$WORK"

printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
