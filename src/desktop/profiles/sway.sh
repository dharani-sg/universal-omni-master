#!/bin/sh
desktop_profile_sway() {
    case "$1" in
        kind) printf 'wayland\n' ;;
        support) printf 'stable\n' ;;
        required) printf 'sway\n' ;;
        recommended)
            printf 'swaybg waybar foot fuzzel mako grim slurp wl-clipboard xdg-desktop-portal-wlr xdg-desktop-portal-gtk\n'
            ;;
        binary) printf 'sway\n' ;;
        session) printf 'sway.desktop\n' ;;
        login_manager) printf 'greetd\n' ;;
        *) return 2 ;;
    esac
}
