#!/bin/sh
desktop_profile_hyprland() {
    case "$1" in
        kind) printf 'wayland\n' ;;
        support) printf 'conditional\n' ;;
        required) printf 'hyprland\n' ;;
        recommended)
            printf 'xdg-desktop-portal-hyprland xdg-desktop-portal-gtk kitty waybar hyprpaper hypridle hyprlock fuzzel grim slurp wl-clipboard\n'
            ;;
        binary) printf 'Hyprland hyprland\n' ;;
        session) printf 'hyprland.desktop\n' ;;
        login_manager) printf 'greetd\n' ;;
        *) return 2 ;;
    esac
}
