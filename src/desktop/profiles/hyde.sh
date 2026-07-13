#!/bin/sh
desktop_profile_hyde() {
    case "$1" in
        kind) printf 'external\n' ;;
        support) printf 'manual-review\n' ;;
        required) printf '\n' ;;
        recommended) printf '\n' ;;
        binary) printf '\n' ;;
        session) printf '\n' ;;
        login_manager) printf 'none\n' ;;
        *) return 2 ;;
    esac
}
