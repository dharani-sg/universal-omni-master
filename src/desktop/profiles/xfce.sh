#!/bin/sh
desktop_profile_xfce() {
    case "$1" in
        kind) printf 'x11\n' ;;
        support) printf 'stable\n' ;;
        required) printf 'xfce4-session xfce4-panel xfce4-settings xfwm4 thunar\n' ;;
        recommended) printf 'xfce4-terminal xfce4-power-manager network-manager-applet\n' ;;
        binary) printf 'startxfce4\n' ;;
        session) printf 'xfce.desktop\n' ;;
        login_manager) printf 'lightdm\n' ;;
        *) return 2 ;;
    esac
}
