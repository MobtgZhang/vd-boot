#!/bin/bash
# Chroot helper functions

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prepare chroot environment
prepare_chroot() {
    local mnt="$1"
    [ -d "$mnt" ] || err "Mount point does not exist: $mnt"
    
    mount -t proc none "$mnt/proc" 2>/dev/null || true
    mount -t sysfs none "$mnt/sys" 2>/dev/null || true
    mount -o bind /dev "$mnt/dev" 2>/dev/null || true
    mount -t devpts none "$mnt/dev/pts" 2>/dev/null || true
    mkdir -p "$mnt/run"
    mount -o bind /run "$mnt/run" 2>/dev/null || true
}

# Cleanup chroot
cleanup_chroot() {
    local mnt="$1"
    sync
    umount "$mnt/run" 2>/dev/null || true
    umount "$mnt/dev/pts" 2>/dev/null || true
    umount "$mnt/dev" 2>/dev/null || true
    umount "$mnt/sys" 2>/dev/null || true
    umount "$mnt/proc" 2>/dev/null || true
}

# Run command in chroot (set locale to avoid perl warnings)
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
            local module_dir="$mnt/usr/lib/dracut/modules.d/90vhdboot"
            local script=""
            [ "$boot_mode" = "kloop" ] && script="vhdmount-kloop.sh"
            [ "$boot_mode" = "vloop" ] && script="vhdmount-vloop.sh"

            # Install as dracut hook
            mkdir -p "$hook_dir"
            cp "$REBUILD2_ROOT/boot/$script" "$hook_dir/10-vhdmount.sh"
            chmod +x "$hook_dir/10-vhdmount.sh"

            # Also install as dracut module for better compatibility
            mkdir -p "$module_dir"
            cp "$REBUILD2_ROOT/boot/$script" "$module_dir/vhdmount.sh"
            chmod +x "$module_dir/vhdmount.sh"
            cat > "$module_dir/module-setup.sh" << 'MODEOF'
#!/bin/bash
check() { return 0; }
depends() { return 0; }
install() {
    inst_hook pre-mount 10 "$moddir/vhdmount.sh"
    inst_multiple blkid losetup kpartx partx 2>/dev/null || true
    inst_multiple mount.ntfs-3g ntfs-3g 2>/dev/null || true
    dracut_instmods squashfs overlay 2>/dev/null || true
}
MODEOF
            chmod +x "$module_dir/module-setup.sh"

            # Copy dracut configuration
            if [ -f "$REBUILD2_ROOT/config/dracut-vhdboot.conf" ]; then
                mkdir -p "$mnt/etc/dracut.conf.d"
                cp "$REBUILD2_ROOT/config/dracut-vhdboot.conf" "$mnt/etc/dracut.conf.d/vhdboot.conf"
            fi
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
            local mods="$mnt/etc/initramfs-tools/modules"
            [ -f "$mods" ] || { mkdir -p "$(dirname "$mods")"; touch "$mods"; }
            for mod in loop fuse dm_mod squashfs overlay; do
                grep -q "^${mod}$" "$mods" 2>/dev/null || echo "$mod" >> "$mods"
            done
            ;;
        *) err "Unsupported initramfs method: $initramfs_method (supported: dracut, mkinitramfs, mkinitcpio)" ;;
    esac
    debug "Installed vhdboot ($boot_mode) via $initramfs_method"
}

# Copy vmlinuz and initramfs-vhdboot.img to output dir (same dir as VHD/VMDK/VDI)
copy_boot_files_to_output() {
    local mnt="$1" output="$2"
    local outdir="$(dirname "$output")"
    mkdir -p "$outdir"
    
    local vk=""
    [ -f "$mnt/boot/vmlinuz-vhdboot" ] && vk="$mnt/boot/vmlinuz-vhdboot"
    [ -z "$vk" ] && [ -f "$mnt/boot/vmlinuz" ] && vk="$mnt/boot/vmlinuz"
    [ -z "$vk" ] && vk=$(ls "$mnt/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1)
    if [ -n "$vk" ] && [ -f "$vk" ]; then
        cp "$vk" "$outdir/vmlinuz"
        info "Copied vmlinuz to $outdir/"
    else
        warn "vmlinuz not found in $mnt/boot/, skipping copy"
    fi
    
    local initrd=""
    [ -f "$mnt/boot/initramfs-vhdboot.img" ] && initrd="$mnt/boot/initramfs-vhdboot.img"
    [ -z "$initrd" ] && [ -f "$mnt/boot/initrd-vhdboot.img" ] && initrd="$mnt/boot/initrd-vhdboot.img"
    [ -z "$initrd" ] && initrd=$(ls "$mnt/boot/initrd.img-"* 2>/dev/null | sort -V | tail -1)
    [ -z "$initrd" ] && initrd=$(ls "$mnt/boot/initramfs-"*.img 2>/dev/null | sort -V | tail -1)
    if [ -n "$initrd" ] && [ -f "$initrd" ]; then
        cp "$initrd" "$outdir/initramfs-vhdboot.img"
        info "Copied initramfs-vhdboot.img to $outdir/"
    else
        warn "initramfs-vhdboot.img not found in $mnt/boot/, skipping copy"
    fi
}

# Build initramfs (inside chroot), supports dracut / mkinitramfs / mkinitcpio
build_initramfs() {
    local mnt="$1" boot_mode="$2" initramfs_method="${3:-dracut}"
    
    install_vhdboot "$mnt" "$boot_mode" "$initramfs_method"
    
    # Detect kernel version in chroot
    local kver=""
    kver=$(ls "$mnt/lib/modules" 2>/dev/null | sort -V | tail -1)
    [ -z "$kver" ] && kver=$(run_chroot "$mnt" ls /lib/modules 2>/dev/null | sort -V | tail -1)
    
    info "Building initramfs ($initramfs_method, kernel: ${kver:-unknown})..."
    
    case "$initramfs_method" in
        dracut)
            if [ ! -f "$mnt/usr/bin/dracut" ] && [ ! -f "$mnt/usr/sbin/dracut" ]; then
                err "dracut not found in chroot, please ensure dracut is installed"
            fi
            run_chroot "$mnt" dracut -f --no-hostonly ${kver:+--kver "$kver"} \
                --install "blkid losetup kpartx partx mount.fuse mount.ntfs-3g ntfs-3g shutdown lvm vgchange vgscan dmsetup" \
                --add-drivers "fuse dm-mod loop squashfs overlay" \
                -o "plymouth btrfs crypt" \
                /boot/initramfs-vhdboot.img
            ;;
        mkinitcpio)
            if [ ! -f "$mnt/usr/bin/mkinitcpio" ]; then
                err "mkinitcpio not found in chroot, please ensure mkinitcpio is installed"
            fi
            local config="$REBUILD2_ROOT/config/mkinitcpio-${boot_mode}.conf"
            [ -f "$config" ] || config=""
            if [ -n "$config" ]; then
                cp "$config" "$mnt/etc/mkinitcpio-vhdboot.conf"
                run_chroot "$mnt" mkinitcpio -c /etc/mkinitcpio-vhdboot.conf \
                    ${kver:+-k "$kver"} -g /boot/initramfs-vhdboot.img
            else
                run_chroot "$mnt" mkinitcpio ${kver:+-k "$kver"} -g /boot/initramfs-vhdboot.img
            fi
            ;;
        mkinitramfs)
            [ -z "$kver" ] && err "Kernel modules directory /lib/modules not found"
            if [ -f "$mnt/usr/sbin/mkinitramfs" ]; then
                run_chroot "$mnt" mkinitramfs -k "$kver" -o /boot/initramfs-vhdboot.img
            elif [ -f "$mnt/usr/bin/mkinitramfs" ]; then
                run_chroot "$mnt" mkinitramfs -k "$kver" -o /boot/initramfs-vhdboot.img
            else
                err "mkinitramfs not found in chroot, please install initramfs-tools"
            fi
            ;;
        *) err "Unsupported initramfs method: $initramfs_method" ;;
    esac
    
    # Verify initramfs was created
    if [ -f "$mnt/boot/initramfs-vhdboot.img" ]; then
        local size=$(du -h "$mnt/boot/initramfs-vhdboot.img" | cut -f1)
        info "initramfs built successfully ($size)"
    else
        warn "initramfs-vhdboot.img may not have been created"
    fi
}
