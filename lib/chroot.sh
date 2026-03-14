#!/bin/bash
# Chroot helper functions

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$LIB_DIR/../config/initramfs-defaults.conf" ] && source "$LIB_DIR/../config/initramfs-defaults.conf"

# Prepare chroot environment
prepare_chroot() {
    local mnt="$1"
    [ -d "$mnt" ] || err "Mount point does not exist: $mnt"
    
    mount -t proc none "$mnt/proc"
    mount -t sysfs none "$mnt/sys"
    mount -o bind /dev "$mnt/dev"
    mount -t devpts none "$mnt/dev/pts"
    mount -o bind /run "$mnt/run" 2>/dev/null || mkdir -p "$mnt/run" && mount -o bind /run "$mnt/run"
}

# Cleanup chroot
cleanup_chroot() {
    local mnt="$1"
    umount "$mnt/run" 2>/dev/null || true
    umount "$mnt/dev/pts" 2>/dev/null || true
    umount "$mnt/dev" 2>/dev/null || true
    umount "$mnt/sys" 2>/dev/null || true
    umount "$mnt/proc" 2>/dev/null || true
}

# Run command in chroot (set locale to avoid perl: warning: Falling back to the standard locale ("C"))
run_chroot() {
    local mnt="$1"
    shift
    chroot "$mnt" env LANG=C.UTF-8 LC_ALL=C.UTF-8 "$@"
}

# Install kloop/vloop boot support (different install method per initramfs)
install_vhdboot() {
    local mnt="$1" boot_mode="$2" initramfs_method="${3:-dracut}"
    
    [ "$boot_mode" = "kloop" ] || [ "$boot_mode" = "vloop" ] || err "boot_mode must be kloop or vloop"
    
    case "$initramfs_method" in
        dracut)
            local hook_dir="$mnt/lib/dracut/hooks/pre-mount"
            local script=""
            [ "$boot_mode" = "kloop" ] && script="vhdmount-kloop.sh"
            [ "$boot_mode" = "vloop" ] && script="vhdmount-vloop.sh"
            mkdir -p "$hook_dir"
            cp "$REBUILD2_ROOT/boot/$script" "$hook_dir/10-vhdmount.sh"
            chmod +x "$hook_dir/10-vhdmount.sh"
            ;;
        mkinitcpio)
            mkdir -p "$mnt/usr/lib/initcpio/install" "$mnt/usr/lib/initcpio/hooks"
            cp "$REBUILD2_ROOT/boot/mkinitcpio-install-vhdboot" "$mnt/usr/lib/initcpio/install/vhdboot"
            cp "$REBUILD2_ROOT/boot/mkinitcpio-hooks-vhdboot" "$mnt/usr/lib/initcpio/hooks/vhdboot"
            chmod +x "$mnt/usr/lib/initcpio/install/vhdboot" "$mnt/usr/lib/initcpio/hooks/vhdboot"
            ;;
        mkinitramfs)
            mkdir -p "$mnt/usr/share/initramfs-tools/scripts/init-premount"
            cp "$REBUILD2_ROOT/boot/vhdmount-initramfs-tools.sh" "$mnt/usr/share/initramfs-tools/scripts/init-premount/vhdboot"
            chmod +x "$mnt/usr/share/initramfs-tools/scripts/init-premount/vhdboot"
            # Ensure modules include required modules
            local mods="$mnt/etc/initramfs-tools/modules"
            [ -f "$mods" ] || touch "$mods"
            for mod in loop fuse dm_mod; do
                grep -q "^${mod}$" "$mods" 2>/dev/null || echo "$mod" >> "$mods"
            done
            ;;
        *) err "Unsupported initramfs method: $initramfs_method (supported: dracut, mkinitramfs, mkinitcpio)" ;;
    esac
}

# Copy vmlinuz and initramfs-vhdboot.img to output dir (same dir as VHD/VMDK/VDI)
# For external kernel boot: GRUB loopback cannot parse VHD/VMDK/VDI format
copy_boot_files_to_output() {
    local mnt="$1" output="$2"
    local outdir="$(dirname "$output")"
    mkdir -p "$outdir"
    
    local vk=""
    [ -f "$mnt/boot/vmlinuz-vhdboot" ] && vk="$mnt/boot/vmlinuz-vhdboot"
    [ -z "$vk" ] && [ -f "$mnt/boot/vmlinuz" ] && vk="$mnt/boot/vmlinuz"
    [ -z "$vk" ] && vk=$(ls "$mnt/boot/vmlinuz-"* 2>/dev/null | head -1)
    if [ -n "$vk" ] && [ -f "$vk" ]; then
        cp "$vk" "$outdir/vmlinuz"
        info "Copied vmlinuz to $outdir/"
    else
        warn "vmlinuz not found, skipping copy"
    fi
    
    local initrd=""
    [ -f "$mnt/boot/initramfs-vhdboot.img" ] && initrd="$mnt/boot/initramfs-vhdboot.img"
    [ -z "$initrd" ] && [ -f "$mnt/boot/initrd-vhdboot.img" ] && initrd="$mnt/boot/initrd-vhdboot.img"
    [ -z "$initrd" ] && initrd=$(ls "$mnt/boot/initrd.img-"* 2>/dev/null | head -1)
    if [ -n "$initrd" ] && [ -f "$initrd" ]; then
        cp "$initrd" "$outdir/initramfs-vhdboot.img"
        info "Copied initramfs-vhdboot.img to $outdir/"
    else
        warn "initramfs-vhdboot.img not found, skipping copy"
    fi
}

# Build initramfs (inside chroot), supports dracut / mkinitramfs / mkinitcpio
build_initramfs() {
    local mnt="$1" boot_mode="$2" initramfs_method="${3:-dracut}"
    
    install_vhdboot "$mnt" "$boot_mode" "$initramfs_method"
    
    case "$initramfs_method" in
        dracut)
            [ -f "$mnt/usr/bin/dracut" ] || err "dracut not found, please install dracut"
            local kver=""
            kver=$(run_chroot "$mnt" ls /lib/modules 2>/dev/null | head -1)
            run_chroot "$mnt" dracut -f --no-hostonly ${kver:+--kver "$kver"} \
                --install "blkid losetup kpartx partx mount.fuse mount.ntfs-3g ntfs-3g shutdown lvm vgchange vgscan dmsetup" \
                --add-drivers "fuse dm-mod loop" \
                -o "plymouth btrfs crypt" \
                /boot/initramfs-vhdboot.img
            ;;
        mkinitcpio)
            [ -f "$mnt/usr/bin/mkinitcpio" ] || err "mkinitcpio not found, please install mkinitcpio"
            local config="$REBUILD2_ROOT/config/mkinitcpio-${boot_mode}.conf"
            [ -f "$config" ] || config=""
            local kver=""
            kver=$(run_chroot "$mnt" ls /lib/modules 2>/dev/null | head -1)
            if [ -n "$config" ]; then
                cp "$config" "$mnt/etc/mkinitcpio-vhdboot.conf"
                run_chroot "$mnt" mkinitcpio -c /etc/mkinitcpio-vhdboot.conf \
                    ${kver:+-k "$kver"} -g /boot/initramfs-vhdboot.img
            else
                run_chroot "$mnt" mkinitcpio ${kver:+-k "$kver"} -g /boot/initramfs-vhdboot.img
            fi
            ;;
        mkinitramfs)
            local kver=""
            kver=$(run_chroot "$mnt" ls /lib/modules 2>/dev/null | head -1)
            [ -z "$kver" ] && err "Kernel modules directory /lib/modules not found"
            if [ -f "$mnt/usr/sbin/mkinitramfs" ]; then
                run_chroot "$mnt" mkinitramfs -k "$kver" -o /boot/initramfs-vhdboot.img
            else
                err "mkinitramfs not found, please install initramfs-tools"
            fi
            ;;
        *) err "Unsupported initramfs method: $initramfs_method" ;;
    esac
}
