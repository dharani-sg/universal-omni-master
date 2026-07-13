#!/bin/sh
desktop_profile_dwm() {
    case "$1" in
        kind) printf 'x11\n' ;;
        support) printf 'conditional\n' ;;
        required) printf 'dwm dmenu\n' ;;
        recommended) printf 'xorg-server xterm feh\n' ;;
        binary) printf 'dwm\n' ;;
        session) printf 'dwm.desktop\n' ;;
        login_manager) printf 'lightdm\n' ;;
        *) return 2 ;;
    esac
}
