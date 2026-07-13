#!/bin/sh
desktop_profile_mango() {
    case "$1" in
        kind) printf 'wayland\n' ;;
        support) printf 'experimental\n' ;;
        required) printf 'mango\n' ;;
        recommended) printf 'waybar foot fuzzel mako xdg-desktop-portal-wlr\n' ;;
        binary) printf 'mango\n' ;;
        session) printf 'mango.desktop\n' ;;
        login_manager) printf 'greetd\n' ;;
        *) return 2 ;;
    esac
}
