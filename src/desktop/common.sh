#!/bin/sh
# src/desktop/common.sh — M27 desktop/WM provisioning core.
# POSIX, BusyBox ash-safe, zero eval.

DESKTOP_ROOT="${DESKTOP_ROOT:-/}"
DESKTOP_AUDIT_LOG="${DESKTOP_AUDIT_LOG:-/var/log/omni-audit.json}"

desktop_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'desktop: REFUSING mutation — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    return 0
}

_desktop_json_escape() {
    printf '%s' "$1" | tr -d '\000-\037' |
        sed 's/\\/\\\\/g; s/"/\\"/g'
}

desktop_detect_distro() {
    _root="${1:-$DESKTOP_ROOT}"
    _file="$_root/etc/os-release"
    [ -f "$_file" ] || { printf 'unknown\n'; return 0; }
    _line=$(grep '^ID=' "$_file" 2>/dev/null | head -1)
    _id=${_line#ID=}
    _id=$(printf '%s' "$_id" | tr -d '"')
    case "$_id" in
        ubuntu) printf 'ubuntu\n' ;;
        debian) printf 'debian\n' ;;
        alpine) printf 'alpine\n' ;;
        arch|archlinux) printf 'arch\n' ;;
        artix) printf 'artix\n' ;;
        void|voidlinux) printf 'void\n' ;;
        chimera) printf 'chimera\n' ;;
        *) printf '%s\n' "${_id:-unknown}" ;;
    esac
}

desktop_detect_init() {
    _root="${1:-$DESKTOP_ROOT}"
    [ -d "$_root/run/systemd/system" ] && { printf 'systemd\n'; return 0; }
    [ -d "$_root/etc/runlevels" ] && { printf 'openrc\n'; return 0; }
    [ -d "$_root/etc/runit" ] && { printf 'runit\n'; return 0; }
    [ -d "$_root/etc/dinit.d" ] && { printf 'dinit\n'; return 0; }
    [ -d "$_root/etc/s6-rc" ] && { printf 's6\n'; return 0; }
    printf 'unknown\n'
}

desktop_profile_query() {
    _profile="$1"
    _field="$2"
    case "$_profile" in
        niri)       desktop_profile_niri "$_field" ;;
        sway)       desktop_profile_sway "$_field" ;;
        hyprland)   desktop_profile_hyprland "$_field" ;;
        xfce)       desktop_profile_xfce "$_field" ;;
        plasma)     desktop_profile_plasma "$_field" ;;
        awesome)    desktop_profile_awesome "$_field" ;;
        fluxbox)    desktop_profile_fluxbox "$_field" ;;
        dwm)        desktop_profile_dwm "$_field" ;;
        mango)      desktop_profile_mango "$_field" ;;
        quickshell) desktop_profile_quickshell "$_field" ;;
        hyde)       desktop_profile_hyde "$_field" ;;
        *) return 2 ;;
    esac
}

desktop_list_profiles() {
    for _profile in niri sway hyprland xfce plasma awesome fluxbox dwm mango quickshell hyde; do
        printf '%-12s kind=%-8s support=%s\n' \
            "$_profile" \
            "$(desktop_profile_query "$_profile" kind)" \
            "$(desktop_profile_query "$_profile" support)"
    done
}

desktop_in_target() {
    _root="$1"
    shift
    if [ "$_root" = "/" ]; then
        "$@"
    else
        chroot "$_root" "$@"
    fi
}

desktop_pkg_available() {
    _root="$1"
    _distro="$2"
    _pkg="$3"

    case "$_pkg" in
        ''|*[!A-Za-z0-9+_.:@-]*) return 1 ;;
    esac

    case "$_distro" in
        alpine)
            desktop_in_target "$_root" apk add --simulate "$_pkg" >/dev/null 2>&1
            ;;
        arch|artix)
            desktop_in_target "$_root" pacman -Si "$_pkg" >/dev/null 2>&1
            ;;
        void)
            desktop_in_target "$_root" xbps-query -R "$_pkg" >/dev/null 2>&1
            ;;
        debian|ubuntu)
            desktop_in_target "$_root" apt-cache show "$_pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

desktop_base_packages() {
    case "$1" in
        alpine)
            printf 'dbus elogind polkit-elogind seatd pipewire pipewire-pulse wireplumber alsa-utils bluez bluez-utils brightnessctl networkmanager xdg-user-dirs xdg-utils font-dejavu\n'
            ;;
        arch)
            printf 'dbus polkit seatd pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils bluez bluez-utils brightnessctl networkmanager xdg-user-dirs xdg-utils noto-fonts\n'
            ;;
        artix)
            printf 'dbus elogind polkit seatd pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils bluez bluez-utils brightnessctl networkmanager xdg-user-dirs xdg-utils ttf-dejavu\n'
            ;;
        void)
            printf 'dbus elogind polkit seatd pipewire wireplumber alsa-utils bluez brightnessctl NetworkManager xdg-user-dirs xdg-utils dejavu-fonts-ttf\n'
            ;;
        debian|ubuntu)
            printf 'dbus-user-session policykit-1 seatd pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils bluez brightnessctl network-manager xdg-user-dirs xdg-utils fonts-dejavu-core\n'
            ;;
        *)
            printf '\n'
            ;;
    esac
}

desktop_plan_profile() {
    _profile="$1"
    _root="${2:-$DESKTOP_ROOT}"
    _distro="${3:-$(desktop_detect_distro "$_root")}"
    _allow_experimental="${4:-0}"

    _kind=$(desktop_profile_query "$_profile" kind) || {
        printf 'desktop: unknown profile %s\n' "$_profile" >&2
        return 2
    }
    _support=$(desktop_profile_query "$_profile" support)

    case "$_kind" in
        external)
            printf 'profile=%s status=external_manual_review\n' "$_profile"
            return 3
            ;;
        addon)
            ;;
    esac

    if [ "$_support" = "experimental" ] && [ "$_allow_experimental" -ne 1 ]; then
        printf 'profile=%s status=experimental_requires_opt_in\n' "$_profile"
        return 3
    fi

    _required=$(desktop_profile_query "$_profile" required)
    _recommended=$(desktop_profile_query "$_profile" recommended)
    _base=$(desktop_base_packages "$_distro")
    _missing=0

    printf 'profile=%s distro=%s kind=%s support=%s\n' \
        "$_profile" "$_distro" "$_kind" "$_support"

    for _pkg in $_required; do
        if desktop_pkg_available "$_root" "$_distro" "$_pkg"; then
            printf 'required.available=%s\n' "$_pkg"
        else
            printf 'required.missing=%s\n' "$_pkg"
            _missing=1
        fi
    done

    for _pkg in $_base $_recommended; do
        if desktop_pkg_available "$_root" "$_distro" "$_pkg"; then
            printf 'optional.available=%s\n' "$_pkg"
        else
            printf 'optional.unavailable=%s\n' "$_pkg"
        fi
    done

    return "$_missing"
}

desktop_install_packages() {
    _root="$1"
    _distro="$2"
    shift 2
    [ $# -gt 0 ] || return 0

    case "$_distro" in
        alpine)
            desktop_in_target "$_root" apk add --no-cache "$@"
            ;;
        arch|artix)
            desktop_in_target "$_root" pacman -S --needed --noconfirm "$@"
            ;;
        void)
            desktop_in_target "$_root" xbps-install -S -y "$@"
            ;;
        debian|ubuntu)
            desktop_in_target "$_root" apt-get install -y "$@"
            ;;
        *)
            return 2
            ;;
    esac
}

desktop_enable_core_services() {
    _root="$1"
    _init="$2"
    _login_manager="$3"

    command -v deploy_enable_services >/dev/null 2>&1 || {
        printf 'desktop: deploy service abstraction unavailable\n' >&2
        return 1
    }

    case "$_init" in
        systemd)
            deploy_enable_services "$_root" "$_init" \
                dbus NetworkManager bluetooth "$_login_manager"
            ;;
        openrc)
            deploy_enable_services "$_root" "$_init" \
                dbus networkmanager bluetooth seatd "$_login_manager"
            ;;
        runit)
            deploy_enable_services "$_root" "$_init" \
                dbus NetworkManager bluetoothd seatd "$_login_manager"
            ;;
        dinit|s6)
            deploy_enable_services "$_root" "$_init" \
                dbus NetworkManager bluetooth seatd "$_login_manager"
            ;;
        *)
            printf 'desktop: unknown init; service enablement skipped\n' >&2
            return 1
            ;;
    esac
}

desktop_telemetry_percent() {
    _distro="$1"
    _profile="$2"
    _package="$3"
    _log="${4:-$DESKTOP_AUDIT_LOG}"
    _co=0
    _total=0

    if [ -f "$_log" ]; then
        _stats=$(awk -v d="$_distro" -v p="$_profile" -v pkg="$_package" '
            /"event":"desktop_install_result"/ &&
            $0 ~ "\"distro\":\"" d "\"" &&
            $0 ~ "\"profile\":\"" p "\"" {
                total++
                if ($0 ~ "\"packages\":\"[^\"]*" pkg) co++
            }
            END { print (co+0), (total+0) }
        ' "$_log")
        _co=${_stats%% *}
        _total=${_stats#* }
    fi

    printf '%s\n' "$(( (_co + 1) * 100 / (_total + 2) ))"
}

desktop_success_percent() {
    _distro="$1"
    _profile="$2"
    _log="${3:-$DESKTOP_AUDIT_LOG}"
    _ok=0
    _total=0

    if [ -f "$_log" ]; then
        _stats=$(awk -v d="$_distro" -v p="$_profile" '
            /"event":"desktop_install_result"/ &&
            $0 ~ "\"distro\":\"" d "\"" &&
            $0 ~ "\"profile\":\"" p "\"" {
                total++
                if ($0 ~ "\"status\":\"success\"") ok++
            }
            END { print (ok+0), (total+0) }
        ' "$_log")
        _ok=${_stats%% *}
        _total=${_stats#* }
    fi

    printf '%s\n' "$(( (_ok + 1) * 100 / (_total + 2) ))"
}

desktop_verify_static() {
    _profile="$1"
    _root="${2:-$DESKTOP_ROOT}"
    _failed=0

    _binaries=$(desktop_profile_query "$_profile" binary)
    _binary_ok=0
    for _bin in $_binaries; do
        if [ -x "$_root/usr/bin/$_bin" ] ||
           [ -x "$_root/usr/local/bin/$_bin" ]; then
            _binary_ok=1
        fi
    done
    [ "$_binary_ok" -eq 1 ] || {
        printf 'desktop_verify: compositor/session binary missing\n' >&2
        _failed=1
    }

    _sessions=$(desktop_profile_query "$_profile" session)
    if [ -n "$_sessions" ]; then
        _session_ok=0
        for _session in $_sessions; do
            [ -f "$_root/usr/share/wayland-sessions/$_session" ] &&
                _session_ok=1
            [ -f "$_root/usr/share/xsessions/$_session" ] &&
                _session_ok=1
        done
        [ "$_session_ok" -eq 1 ] || {
            printf 'desktop_verify: session desktop file missing\n' >&2
            _failed=1
        }
    fi

    [ "$_failed" -eq 0 ]
}

desktop_mark_firstboot_pending() {
    desktop_guard_mutation || return $?
    _root="$1"
    _profile="$2"
    _user="$3"
    _file="$_root/var/lib/omni-master/desktop-firstboot.pending"
    mkdir -p "${_file%/*}" || return 1
    {
        printf 'profile=%s\n' "$_profile"
        printf 'user=%s\n' "$_user"
    } > "$_file"
}

desktop_emit_event() {
    _root="$1"
    _distro="$2"
    _profile="$3"
    _status="$4"
    _packages="$5"
    _log="$_root/var/log/omni-audit.json"
    mkdir -p "${_log%/*}" 2>/dev/null || true
    printf '{"event":"desktop_install_result","distro":"%s","profile":"%s","status":"%s","packages":"%s"}\n' \
        "$(_desktop_json_escape "$_distro")" \
        "$(_desktop_json_escape "$_profile")" \
        "$(_desktop_json_escape "$_status")" \
        "$(_desktop_json_escape "$_packages")" >> "$_log"
}

desktop_install_profile() {
    desktop_guard_mutation || return $?

    _profile="$1"
    _root="$2"
    _distro="$3"
    _init="$4"
    _user="$5"
    _login_manager="$6"
    _allow_experimental="$7"

    _kind=$(desktop_profile_query "$_profile" kind) || return 2
    case "$_kind" in
        external)
            printf 'desktop: external preset requires manual review\n' >&2
            return 3
            ;;
    esac

    desktop_plan_profile "$_profile" "$_root" "$_distro" \
        "$_allow_experimental" >/dev/null || return $?

    _packages=""
    for _pkg in \
        $(desktop_profile_query "$_profile" required) \
        $(desktop_base_packages "$_distro") \
        $(desktop_profile_query "$_profile" recommended)
    do
        if desktop_pkg_available "$_root" "$_distro" "$_pkg"; then
            case " $_packages " in
                *" $_pkg "*) : ;;
                *) _packages="${_packages}${_packages:+ }${_pkg}" ;;
            esac
        fi
    done

    [ -n "$_packages" ] || return 1
    desktop_install_packages "$_root" "$_distro" $_packages || {
        desktop_emit_event "$_root" "$_distro" "$_profile" failed "$_packages"
        return 1
    }

    if [ "$_login_manager" = "auto" ]; then
        _login_manager=$(desktop_profile_query "$_profile" login_manager)
    fi

    if [ "$_login_manager" != "none" ]; then
        if desktop_pkg_available "$_root" "$_distro" "$_login_manager"; then
            desktop_install_packages "$_root" "$_distro" "$_login_manager" ||
                return 1
            desktop_enable_core_services "$_root" "$_init" "$_login_manager" ||
                return 1
        fi
    else
        desktop_enable_core_services "$_root" "$_init" none || true
    fi

    if ! desktop_verify_static "$_profile" "$_root"; then
        desktop_emit_event "$_root" "$_distro" "$_profile" failed "$_packages"
        return 1
    fi

    desktop_mark_firstboot_pending "$_root" "$_profile" "$_user" || return 1
    desktop_emit_event "$_root" "$_distro" "$_profile" success "$_packages"
    return 0
}
