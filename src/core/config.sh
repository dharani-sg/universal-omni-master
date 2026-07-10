#!/bin/sh
# config.sh — hybrid TOML. Pure-POSIX subset parser (key="value", [section]).
# If python3 present AND OMNI_TOML_PYTHON=1, defer to it for full TOML.

toml_get() {
    _file="$1"; _sec="$2"; _key="$3"
    [ -r "$_file" ] || return 1

    if [ "${OMNI_TOML_PYTHON:-0}" = "1" ] && command -v python3 >/dev/null 2>&1; then
        python3 - "$_file" "$_sec" "$_key" <<'PY' 2>/dev/null
import sys
try:
    try:
        import tomllib as t
        data = t.load(open(sys.argv[1], "rb"))
    except Exception:
        import tomli as t
        data = t.load(open(sys.argv[1], "rb"))
    sec, key = sys.argv[2], sys.argv[3]
    node = data.get(sec, {}) if sec else data
    v = node.get(key)
    if v is not None:
        print(v if not isinstance(v, bool) else ("true" if v else "false"))
except Exception:
    sys.exit(1)
PY
        return $?
    fi

    # POSIX subset parser (busybox-awk safe: no [[:space:]])
    awk -v sec="$_sec" -v k="$_key" '
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
        /^[ \t]*#/ { next }
        /^[ \t]*\[/ {
            cur=$0; gsub(/[\[\] \t]/,"",cur); insec=(cur==sec); next
        }
        {
            if (sec!="" && !insec) next
            eq=index($0,"=")
            if (eq>0) {
                kk=trim(substr($0,1,eq-1))
                vv=trim(substr($0,eq+1))
                gsub(/^"|"$/,"",vv)
                gsub(/^'\''|'\''$/,"",vv)
                if (kk==k) { print vv; exit }
            }
        }
    ' "$_file"
}
