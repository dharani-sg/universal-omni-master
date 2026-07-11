# src/tui/installer.fish — wizard that ASSEMBLES an omni-deploy command.
# Dry-run always shown first. Real apply requires typing APPLY. No logic here.
function tui_action_installer
    set -l root (dirname (status filename))/../..
    tui_header "Installer Wizard"
    read -P "Distro (alpine/void/arch/artix/debian): " -l distro
    read -P "Disk (e.g. sda): " -l disk
    read -P "Filesystem [btrfs]: " -l fs;   test -z "$fs";   and set fs btrfs
    read -P "Hostname [omni-linux]: " -l hn; test -z "$hn";  and set hn omni-linux
    read -P "Init (blank = auto): " -l init

    set -l cmd $root/bin/omni-deploy install --distro $distro --disk $disk --fs $fs --hostname $hn
    test -n "$init"; and set -a cmd --init $init

    echo; echo "── DRY-RUN ──"
    tui_run $cmd            # dry-run is omni-deploy's default
    echo
    if tui_confirm "Execute REAL install (DESTROYS /dev/$disk)" APPLY
        tui_run $cmd --apply
    else
        echo "Not applied."
    end
end
