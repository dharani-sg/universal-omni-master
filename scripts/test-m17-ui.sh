#!/bin/sh
# M17 POSIX adaptive UI gate.
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
UI_SH="$ROOT/src/deploy/ui.sh"

PASS=0
FAIL=0

_check()
{
    _label=$1
    _expected=$2
    _actual=$3

    if [ "$_expected" = "$_actual" ]; then
        printf '  PASS %-52s = %s\n' "$_label" "$_actual"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' \
            "$_label" "$_expected" "$_actual"
        FAIL=$((FAIL + 1))
    fi
}

_cleanup()
{
    rm -rf "${WORK:-}"
}

trap '_cleanup' 0 1 2 3 15

printf '%s\n' '=== M17 POSIX Adaptive UI Tests ==='

if sh -n "$UI_SH"; then
    _check "syntax: ui.sh" 0 0
else
    _check "syntax: ui.sh" 0 1
    exit 1
fi

. "$UI_SH"

WORK="${TMPDIR:-/tmp}/omni-m17-test-$$"
MOCK="$WORK/mock"
mkdir -p "$MOCK"

cat > "$MOCK/stty" <<'MOCK_EOF'
#!/bin/sh
if [ "${1:-}" = size ]; then
    printf '24 %s\n' "${MOCK_COLS:-80}"
    exit 0
fi
exit 1
MOCK_EOF
chmod 755 "$MOCK/stty"

OLDPATH=$PATH
PATH="$MOCK:$PATH"
export PATH

_test_layout()
{
    MOCK_COLS=$1
    export MOCK_COLS
    TUI_LAYOUT=
    ui_detect_layout >/dev/null
    printf '%s' "$TUI_LAYOUT"
}

_check "40 columns -> portrait" portrait "$(_test_layout 40)"
_check "80 columns -> compact" compact "$(_test_layout 80)"
_check "120 columns -> landscape" landscape "$(_test_layout 120)"

MOCK_COLS=invalid
export MOCK_COLS
TUI_LAYOUT=
ui_detect_layout >/dev/null
_check "invalid width -> compact fallback" compact "$TUI_LAYOUT"

TUI_LAYOUT=portrait
_menu=$(printf '2\n' | ui_menu Choose alpha beta gamma 2>&1)
case "$_menu" in
    *"1) alpha"*"2) beta"*"3) gamma"*)
        _check "portrait menu is vertical" yes yes ;;
    *)
        _check "portrait menu is vertical" yes no ;;
esac

TUI_LAYOUT=portrait
_selected=$(printf '2\n' | ui_menu Choose alpha beta gamma 2>/dev/null)
_check "menu returns selected item" beta "$_selected"

_rc=0
printf 'bad\n' | ui_menu Choose alpha beta >/dev/null 2>&1 || _rc=$?
_check "menu rejects non-numeric input" 1 "$_rc"

_rc=0
printf '9\n' | ui_menu Choose alpha beta >/dev/null 2>&1 || _rc=$?
_check "menu rejects out-of-range input" 1 "$_rc"

TUI_LAYOUT=portrait
_check "portrait progress" "[#####.....] 50%" "$(ui_progress install 50)"

TUI_LAYOUT=portrait
case "$(ui_progress install 500)" in
    *"100%"*) _check "progress clamps above 100" yes yes ;;
    *)        _check "progress clamps above 100" yes no ;;
esac

TUI_LAYOUT=landscape
case "$(ui_progress install 25)" in
    *install*25%*) _check "landscape progress includes label" yes yes ;;
    *)             _check "landscape progress includes label" yes no ;;
esac

ESC=$(printf '\033')
TUI_LAYOUT=landscape
_banner=$(NO_COLOR=1 ui_banner TEST)
case "$_banner" in
    *"$ESC"*) _check "NO_COLOR suppresses ANSI" no yes ;;
    *)        _check "NO_COLOR suppresses ANSI" no no ;;
esac

_banner=$(TERM=dumb ui_banner TEST)
case "$_banner" in
    *"$ESC"*) _check "TERM=dumb suppresses ANSI" no yes ;;
    *)        _check "TERM=dumb suppresses ANSI" no no ;;
esac

_rc=0
_ui_ansi_ok >/dev/null 2>&1 || _rc=$?
_check "non-tty stdout suppresses ANSI" 1 "$_rc"

TUI_LAYOUT=portrait
_rc=0
printf 'DESTROY\n' | ui_confirm "wipe?" DESTROY >/dev/null 2>&1 || _rc=$?
_check "confirmation accepts exact word" 0 "$_rc"

_rc=0
printf 'destroy\n' | ui_confirm "wipe?" DESTROY >/dev/null 2>&1 || _rc=$?
_check "confirmation rejects wrong case" 1 "$_rc"

TUI_LOG_FILE="$WORK/deploy.log"
TUI_SHOW_LOGS=0
export TUI_LOG_FILE TUI_SHOW_LOGS

_rc=0
OMNI_SYSROOT=/tmp/fx ui_log_toggle >/dev/null 2>&1 || _rc=$?
_check "log toggle fixture guard" 126 "$_rc"

_rc=0
OMNI_SYSROOT=/tmp/fx ui_log blocked >/dev/null 2>&1 || _rc=$?
_check "log write fixture guard" 126 "$_rc"

unset OMNI_SYSROOT
ui_log hidden-message >/dev/null 2>&1
grep -q '^hidden-message$' "$TUI_LOG_FILE"
_check "hidden log stored in file" 0 "$?"

ui_log_toggle >/dev/null
_check "log toggle enables disclosure" 1 "$TUI_SHOW_LOGS"

_visible=$(ui_log visible-message 2>&1)
_check "visible log reaches stderr" visible-message "$_visible"

ui_log_toggle >/dev/null
_check "log toggle disables disclosure" 0 "$TUI_SHOW_LOGS"

PATH=$OLDPATH
export PATH

printf '%s\n' '=================================================='
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"

[ "$FAIL" -eq 0 ]
