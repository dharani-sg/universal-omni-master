#!/bin/sh
desktop_profile_quickshell() {
    case "$1" in
        kind) printf 'addon\n' ;;
        support) printf 'conditional\n' ;;
        required) printf 'quickshell\n' ;;
        recommended) printf 'qt6-svg qt6-imageformats qt6-multimedia qt6-5compat\n' ;;
        binary) printf 'quickshell qs\n' ;;
        session) printf '\n' ;;
        login_manager) printf 'none\n' ;;
        *) return 2 ;;
    esac
}
