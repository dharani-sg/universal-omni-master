
# --- T21: ANSI suppressed when stdout is not a tty (redirected) ----------
_rc=0
( . "$UI_SH"; _ui_ansi_ok ) > /tmp/omni-m17-tty-$$ 2>&1
_rc=$?
rm -f /tmp/omni-m17-tty-$$
if [ "$_rc" -eq 1 ]; then
    _pass "non-tty stdout disables ANSI (_ui_ansi_ok)"
else
    _fail "non-tty stdout disables ANSI (_ui_ansi_ok)" "rc=$_rc"
fi
