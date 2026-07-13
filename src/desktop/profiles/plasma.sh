#!/bin/sh
desktop_profile_plasma() {
    case "$1" in
        kind) printf 'wayland\n' ;;
        support) printf 'stable\n' ;;
        required) printf 'plasma-desktop plasma-workspace\n' ;;
        recommended) printf 'konsole dolphin sddm xdg-desktop-portal-kde\n' ;;
        binary) printf 'startplasma-wayland startplasma-x11\n' ;;
        session) printf 'plasma.desktop plasmawayland.desktop\n' ;;
        login_manager) printf 'sddm\n' ;;
        *) return 2 ;;
    esac
}
