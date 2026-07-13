#!/bin/sh
desktop_profile_awesome() {
    case "$1" in
        kind) printf 'x11\n' ;;
        support) printf 'stable\n' ;;
        required) printf 'awesome\n' ;;
        recommended) printf 'xorg-server xterm rofi picom\n' ;;
        binary) printf 'awesome\n' ;;
        session) printf 'awesome.desktop\n' ;;
        login_manager) printf 'lightdm\n' ;;
        *) return 2 ;;
    esac
}
