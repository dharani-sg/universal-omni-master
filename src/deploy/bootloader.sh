#!/bin/sh
# deploy/bootloader.sh — GRUB and systemd-boot installation.

DEPLOY_BOOTLOADER="${DEPLOY_BOOTLOADER:-auto}"

_detect_best_bootloader() {
    [ -d /sys/firmware/efi ] && echo "systemd-boot" || echo "grub"
}

# Build the kernel cmdline incorporating M4 GPU policy and M5 storage findings
_build_cmdline() {
    _cmdline="mitigations=off random.trust_cpu=on"

    # SATA: stable link speed, NCQ off if cable is degraded
    if detect_storage_types 2>/dev/null | grep -qE 'ssd|hdd'; then
        _cmdline="$_cmdline libata.force=noncq,3.0Gbps"
    fi

    # dGPU: defer at boot if hybrid
    if [ "$(detect_gpu_hybrid 2>/dev/null)" = "yes" ]; then
        _cmdline="$_cmdline modprobe.blacklist=amdgpu,radeon rd.driver.blacklist=amdgpu,radeon"
    fi

    # No-PM: AC-only policy
    _cmdline="$_cmdline snd_hda_intel.power_save=0 snd_hda_intel.power_save_controller=N"
    _cmdline="$_cmdline pcie_aspm=off usbcore.autosuspend=-1"

    # LUKS: add cryptdevice if encryption enabled
    [ "${DEPLOY_ENCRYPT:-0}" = "1" ] && \
        _cmdline="$_cmdline cryptdevice=UUID=${DEPLOY_LUKS_UUID:-<LUKS-UUID>}:cryptroot"

    printf '%s' "$_cmdline"
}

deploy_install_bootloader() {
    _target="${DEPLOY_TARGET:-/mnt}"
    _disk="${DEPLOY_DISK:?DEPLOY_DISK must be set}"
    _init="${DEPLOY_INIT:-openrc}"

    [ "$DEPLOY_BOOTLOADER" = "auto" ] && DEPLOY_BOOTLOADER=$(_detect_best_bootloader)
    log_info "=== BOOTLOADER: $DEPLOY_BOOTLOADER ==="

    # Get root UUID — use UUID to avoid mutable /dev/sdXN paths (research finding #5)
    _root_part="${DEPLOY_ROOT_PART:-/dev/${_disk}2}"
    _root_uuid=$(blkid -s UUID -o value "$_root_part" 2>/dev/null || echo "<UUID>")

    case "$DEPLOY_BOOTLOADER" in
        grub)
            chroot_exec "$_target" grub-install --recheck \
                $([ -d /sys/firmware/efi ] && \
                    echo "--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB" || \
                    echo "--target=i386-pc /dev/$_disk")

            # Inject our cmdline into GRUB defaults before generating config
            _cmdline=$(_build_cmdline)
            grep -q "^GRUB_CMDLINE_LINUX_DEFAULT" "$_target/etc/default/grub" 2>/dev/null && \
                sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$_cmdline\"|" \
                    "$_target/etc/default/grub" || \
                printf 'GRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "$_cmdline" \
                    >> "$_target/etc/default/grub"

            chroot_exec "$_target" grub-mkconfig -o /boot/grub/grub.cfg
            log_info "GRUB installed and configured"
            ;;

        systemd-boot)
            if ! [ -d /sys/firmware/efi ]; then
                log_error "systemd-boot requires UEFI firmware"
                return 1
            fi
            chroot_exec "$_target" bootctl install

            # Write loader.conf
            cat > "$_target/boot/loader/loader.conf" << LDCONF
default  omni-linux.conf
timeout  5
console-mode  max
editor   no
LDCONF

            # Write boot entry (use UUID, not device path)
            _cmdline=$(_build_cmdline)
            _linux="linux"
            _initrd="initramfs-linux.img"
            # microcode prefix if available
            _ucode=""
            [ -f "$_target/boot/intel-ucode.img" ] && _ucode="initrd /intel-ucode.img\n"

            mkdir -p "$_target/boot/loader/entries"
            printf \
'title   Omni Linux (%s)\nlinux   /%s\n%sinitrd  /%s\noptions root=UUID=%s rw %s\n' \
                "$DEPLOY_DISTRO" "$_linux" "$_ucode" "$_initrd" "$_root_uuid" "$_cmdline" \
                > "$_target/boot/loader/entries/omni-linux.conf"

            log_info "systemd-boot installed and configured"
            ;;

        limine)
            log_info "Limine: generating guidance (complete manually after boot)"
            printf \
'/Omni Linux\n  protocol: linux\n  kernel_path: boot():/vmlinuz\n  kernel_cmdline: root=UUID=%s rw %s\n' \
                "$_root_uuid" "$(_build_cmdline)"
            ;;

        *)
            log_error "Unknown bootloader: $DEPLOY_BOOTLOADER"
            return 1
            ;;
    esac
}
