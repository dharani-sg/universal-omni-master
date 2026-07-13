#!/bin/sh
desktop_profile_niri() {
    case "$1" in
        kind) printf 'wayland\n' ;;
        support) printf 'conditional\n' ;;
        required) printf 'niri\n' ;;
        recommended)
            printf 'xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk fuzzel mako waybar alacritty swaybg swayidle swaylock\n'
            ;;
        binary) printf 'niri\n' ;;
        session) printf 'niri.desktop\n' ;;
        login_manager) printf 'greetd\n' ;;
        *) return 2 ;;
    esac
}
