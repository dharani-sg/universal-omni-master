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

printf '%s\n' '=== M27.1 Desktop Telemetry and Hardening Tests ==='

for _file in \
    "$ROOT/src/desktop/common.sh" \
    "$ROOT/src/desktop/telemetry.sh" \
    "$ROOT/bin/omni-desktop"
do
    if sh -n "$_file"; then
        check "syntax: ${_file##*/}" 0 0
    else
        check "syntax: ${_file##*/}" 0 1
    fi
done

. "$ROOT/src/deploy/chroot.sh" 2>/dev/null || true
. "$ROOT/src/deploy/configure.sh" 2>/dev/null || true

for _file in "$ROOT/src/desktop/profiles/"*.sh; do
    . "$_file"
done

. "$ROOT/src/desktop/common.sh"
. "$ROOT/src/desktop/telemetry.sh"

WORK="${TMPDIR:-/tmp}/omni-m271-$$"
FAKE="$WORK/root"
AUDIT="$FAKE/var/log/omni-audit.json"
SERVICE_LOG="$WORK/services.log"

mkdir -p "$FAKE/var/log"
export DESKTOP_PROFILE_DIR="$ROOT/src/desktop/profiles"

_profiles=$(desktop_profile_names)
printf '%s\n' "$_profiles" | grep -q '^niri$'
check "dynamic discovery finds niri" 0 "$?"

check "dynamic dispatch sway kind" \
    wayland "$(desktop_profile_query sway kind)"

_rc=0
desktop_profile_query "bad;profile" kind >/dev/null 2>&1 || _rc=$?
check "malformed profile rejected" 2 "$_rc"

_iteration=1
while [ "$_iteration" -le 9 ]; do
    printf '%s\n' \
        '{"event":"desktop_install_result","distro":"alpine","profile":"niri","status":"success","packages":"wireplumber brightnessctl"}' \
        >> "$AUDIT"
    _iteration=$((_iteration + 1))
done

printf '%s\n' \
    '{"event":"desktop_install_result","distro":"alpine","profile":"niri","status":"failed","packages":"brightnessctl"}' \
    >> "$AUDIT"

_profile_stats=$(desktop_telemetry_profile_stats alpine niri "$AUDIT")
_profile_score=${_profile_stats##*|}
check "Laplace success score" 83 "$_profile_score"

_package_stats=$(desktop_telemetry_package_stats \
    alpine niri wireplumber "$AUDIT")
_package_score=${_package_stats##*|}
check "package adoption score" 83 "$_package_score"

_empty_stats=$(desktop_telemetry_profile_stats alpine sway "$AUDIT")
_empty_score=${_empty_stats##*|}
check "empty sample prior" 50 "$_empty_score"

_table=$(desktop_telemetry_dashboard alpine "$AUDIT" table)
printf '%s\n' "$_table" | grep -q '^PROFILE'
check "dashboard table header" 0 "$?"

_ndjson=$(desktop_telemetry_dashboard alpine "$AUDIT" ndjson)
printf '%s\n' "$_ndjson" | grep -q '"profile":"niri"'
check "dashboard NDJSON output" 0 "$?"

_cli_package=$(
    "$ROOT/bin/omni-desktop" \
        telemetry niri wireplumber \
        --log "$AUDIT" \
        --distro alpine
)
printf '%s\n' "$_cli_package" | grep -q '|83$'
check "CLI telemetry package accepts trailing options" 0 "$?"

_cli_dashboard=$(
    "$ROOT/bin/omni-desktop" \
        telemetry --dashboard \
        --log "$AUDIT" \
        --distro alpine
)
printf '%s\n' "$_cli_dashboard" | grep -q '^PROFILE'
check "CLI telemetry dashboard" 0 "$?"

_rc=0
OMNI_SYSROOT=/tmp/fx desktop_emit_event \
    "$FAKE" alpine niri success pkg >/dev/null 2>&1 || _rc=$?
check "emit event mutation guard" 126 "$_rc"

desktop_pkg_available() {
    return 1
}

_quickshell_plan=$(
    desktop_plan_profile quickshell "$FAKE" alpine 0 || true
)

printf '%s\n' "$_quickshell_plan" | grep -q \
    '^optional.unavailable=pipewire$'
if [ "$?" -eq 0 ]; then
    check "quickshell add-on excludes desktop base packages" no yes
else
    check "quickshell add-on excludes desktop base packages" no no
fi

deploy_enable_services() {
    printf '%s\n' "$*" >> "$SERVICE_LOG"
    return 0
}

desktop_enable_core_services "$FAKE" openrc none >/dev/null 2>&1

if grep -q ' none' "$SERVICE_LOG" 2>/dev/null; then
    check "login-manager none not passed to service layer" no yes
else
    check "login-manager none not passed to service layer" no no
fi

grep -q 'seatd' "$SERVICE_LOG"
check "core seatd service remains enabled" 0 "$?"

rm -rf "$WORK"

printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
