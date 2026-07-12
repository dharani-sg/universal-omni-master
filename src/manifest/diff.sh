#!/bin/sh
# src/manifest/diff.sh — Drift detection and reconciliation logic.
# Requires: manifest_parse() from parser.sh

_manifest_check_package() {
    _pkg=$1
    _expected=$2
    _actual="absent"

    if command -v apk >/dev/null 2>&1; then
        apk info -e "$_pkg" >/dev/null 2>&1 && _actual="present"
    elif command -v xbps-query >/dev/null 2>&1; then
        xbps-query "$_pkg" >/dev/null 2>&1 && _actual="present"
    elif command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Status}' "$_pkg" 2>/dev/null | grep -q "ok installed" && _actual="present"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Q "$_pkg" >/dev/null 2>&1 && _actual="present"
    fi

    [ "$_actual" = "$_expected" ]
}

_manifest_check_service() {
    _svc=$1
    _expected=$2
    _actual="disabled"

    if command -v omni-service >/dev/null 2>&1; then
        omni-service status "$_svc" 2>/dev/null | grep -qi "enabled\|running" && _actual="enabled"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl is-enabled "$_svc" >/dev/null 2>&1 && _actual="enabled"
    fi

    [ "$_actual" = "$_expected" ]
}

_manifest_check_sysctl() {
    _key=$1
    _expected=$2
    _actual=""

    if command -v sysctl >/dev/null 2>&1; then
        _actual=$(sysctl -n "$_key" 2>/dev/null)
    else
        _proc_path="/proc/sys/$(printf '%s' "$_key" | tr '.' '/')"
        if [ -f "$_proc_path" ]; then
            _actual=$(cat "$_proc_path" 2>/dev/null)
        fi
    fi

    [ "$_actual" = "$_expected" ]
}

manifest_diff() {
    manifest_parse "$1" | while IFS= read -r _line; do
        [ -z "$_line" ] && continue

        # Parse 'section.key=value'
        _sec=${_line%%.*}
        _rest=${_line#*.}
        _key=${_rest%%=*}
        _val=${_rest#*=}

        case "$_sec" in
            packages)
                if ! _manifest_check_package "$_key" "$_val"; then
                    if [ "$_val" = "present" ]; then
                        printf 'package_install %s\n' "$_key"
                    elif [ "$_val" = "absent" ]; then
                        printf 'package_remove %s\n' "$_key"
                    fi
                fi
                ;;
            services)
                if ! _manifest_check_service "$_key" "$_val"; then
                    if [ "$_val" = "enabled" ]; then
                        printf 'service_enable %s\n' "$_key"
                    elif [ "$_val" = "disabled" ]; then
                        printf 'service_disable %s\n' "$_key"
                    fi
                fi
                ;;
            sysctl)
                if ! _manifest_check_sysctl "$_key" "$_val"; then
                    printf 'sysctl_set %s %s\n' "$_key" "$_val"
                fi
                ;;
        esac
    done
}

manifest_apply() {
    _ma_file=$1
    _ma_mode=${2:-}

    if [ "$_ma_mode" = "--apply" ]; then
        if [ -n "${OMNI_SYSROOT:-}" ]; then
            printf 'manifest: REFUSING apply — OMNI_SYSROOT set\n' >&2
            return 126
        fi

        manifest_diff "$_ma_file" | while IFS= read -r _cmd; do
            [ -z "$_cmd" ] && continue
            _act=${_cmd%% *}
            _args=${_cmd#* }
            _tgt=${_args%% *}
            _val=${_args#* }

            printf 'Executing: %s\n' "$_cmd"

            case "$_act" in
                package_install)
                    if command -v apk >/dev/null 2>&1; then apk add "$_tgt"
                    elif command -v xbps-install >/dev/null 2>&1; then xbps-install -y "$_tgt"
                    elif command -v apt-get >/dev/null 2>&1; then apt-get install -y "$_tgt"
                    elif command -v pacman >/dev/null 2>&1; then pacman -S --noconfirm "$_tgt"
                    fi ;;
                package_remove)
                    if command -v apk >/dev/null 2>&1; then apk del "$_tgt"
                    elif command -v xbps-remove >/dev/null 2>&1; then xbps-remove -y "$_tgt"
                    elif command -v apt-get >/dev/null 2>&1; then apt-get remove -y "$_tgt"
                    elif command -v pacman >/dev/null 2>&1; then pacman -R --noconfirm "$_tgt"
                    fi ;;
                service_enable)
                    if command -v omni-service >/dev/null 2>&1; then omni-service enable "$_tgt"
                    elif command -v systemctl >/dev/null 2>&1; then systemctl enable "$_tgt"
                    fi ;;
                service_disable)
                    if command -v omni-service >/dev/null 2>&1; then omni-service disable "$_tgt"
                    elif command -v systemctl >/dev/null 2>&1; then systemctl disable "$_tgt"
                    fi ;;
                sysctl_set)
                    if command -v sysctl >/dev/null 2>&1; then sysctl -w "$_tgt=$_val"
                    else
                        _proc_path="/proc/sys/$(printf '%s' "$_tgt" | tr '.' '/')"
                        printf '%s' "$_val" > "$_proc_path"
                    fi ;;
            esac
        done
    else
        # Default to dry-run
        manifest_diff "$_ma_file" | while IFS= read -r _cmd; do
            [ -z "$_cmd" ] && continue
            printf 'Plan: %s\n' "$_cmd"
        done
    fi
}
