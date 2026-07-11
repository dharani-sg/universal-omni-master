#!/usr/bin/env fish
# src/tui/installer.fish — M7 plan and apply wizard.
# ALL mutations require: dry-run display + type disk name + type APPLY.
# Never reimplements partition logic — delegates entirely to omni-deploy.

function tui_action_installer
    # D15: mutation guard before any interaction
    _tui_guard_mutation; or return 126

    tui_header "Installer Wizard"
    echo

    # ── Gather parameters (read-only) ─────────────────────────────────────────
    read --prompt-str "Distro [alpine/void/arch/artix/debian]: " -l _distro
    if test -z "$_distro"
        echo "Distro required."; return 1
    end

    read --prompt-str "Target disk (e.g. sda, nvme0n1): " -l _disk
    if test -z "$_disk"
        echo "Disk required."; return 1
    end

    read --prompt-str "Filesystem [btrfs]: " -l _fs
    if test -z "$_fs"; set _fs btrfs; end

    read --prompt-str "Hostname [omni-linux]: " -l _hn
    if test -z "$_hn"; set _hn omni-linux; end

    read --prompt-str "Init system (blank = auto-detect): " -l _init

    # ── Build command as Fish list — no eval, no string interpolation ─────────
    # D2 fix pattern: explicit list construction
    set -l _cmd $OMNI_ROOT/bin/omni-deploy install \
        --distro $_distro \
        --disk   $_disk \
        --fs     $_fs \
        --hostname $_hn
    if test -n "$_init"
        set -a _cmd --init $_init
    end

    # ── Dry-run: always shown before any confirmation ─────────────────────────
    echo
    tui_separator
    echo "DRY-RUN PLAN (no changes will be made)"
    tui_separator
    tui_run $_cmd
    echo
    tui_separator
    echo "MUTATION CONFIRMATION"
    tui_separator
    echo "  Target disk: /dev/$_disk — ALL DATA WILL BE DESTROYED."
    echo

    # D10 fix: two-step — type disk name, then type APPLY
    if tui_confirm_two "disk identifier" "$_disk" APPLY
        echo
        echo "Acquiring privileges..."
        # privilege escalation is handled by omni-deploy preflight
        tui_run $_cmd --apply
    else
        echo "Aborted — no changes made."
    end
end
