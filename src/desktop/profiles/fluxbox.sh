#!/bin/sh
desktop_profile_fluxbox() {
    case "$1" in
        kind) printf 'x11\n' ;;
        support) printf 'stable\n' ;;
        required) printf 'fluxbox\n' ;;
        recommended) printf 'xorg-server xterm feh picom\n' ;;
        binary) printf 'fluxbox\n' ;;
        session) printf 'fluxbox.desktop\n' ;;
        login_manager) printf 'lightdm\n' ;;
        *) return 2 ;;
    esac
}
