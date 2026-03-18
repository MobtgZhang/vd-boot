#!/bin/bash
# Arch Linux - Build bootable VHD from Tsinghua mirror

set -e
REBUILD2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REBUILD2_ROOT/lib/common.sh"
source "$REBUILD2_ROOT/lib/disk.sh"
source "$REBUILD2_ROOT/lib/chroot.sh"
[ -f "$REBUILD2_ROOT/config/mirrors.conf" ] && source "$REBUILD2_ROOT/config/mirrors.conf"

build() {
    local output="$1" size="${2:-16}" disk_type="${3:-dynamic}" boot_mode="${4:-kloop}" fmt="${5:-vhd}" initramfs_method="${6:-}"
    [ -z "$initramfs_method" ] && initramfs_method="$(get_initramfs_default archlinux)"
    
    check_root
    check_deps
    
    command -v tar >/dev/null || err "tar required"
    command -v zstd >/dev/null || err "zstd required: pacman -S zstd"
    
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    local mnt="$workdir/mnt"
    local bootstrap="$workdir/archlinux-bootstrap.tar.zst"
    local loop_dev=""
    
    mkdir -p "$workdir" "$mnt"
    
    # 1. Create disk (build with raw first, convert at end)
    local raw_disk="$workdir/arch.raw"
    info "Creating disk ${size}GB..."
    truncate -s "${size}G" "$raw_disk"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    # Register cleanup trap
    setup_cleanup_trap "$mnt" "$loop_dev" "$workdir"
    
    if [ -f "$mnt/etc/arch-release" ] || [ -f "$mnt/etc/os-release" ]; then
        info "Detected installed system, skipping bootstrap..."
    else
        # 2. Download bootstrap
        if [ ! -f "$bootstrap" ]; then
            info "Downloading Arch bootstrap from $MIRROR_ARCH_BOOTSTRAP"
            wget -q --show-progress -O "$bootstrap" "$MIRROR_ARCH_BOOTSTRAP" || \
            curl -L -o "$bootstrap" "$MIRROR_ARCH_BOOTSTRAP"
        fi
        
        # 3. Extract bootstrap
        info "Extracting bootstrap..."
        tar -xpf "$bootstrap" -C "$workdir"
        local rootfs="$workdir/root.x86_64"
        [ -d "$rootfs" ] || rootfs="$workdir/root.$(uname -m)"
        [ -d "$rootfs" ] || rootfs=$(find "$workdir" -maxdepth 1 -type d -name "root*" | head -1)
        [ -d "$rootfs" ] || err "root directory not found after extracting bootstrap"
        
        rsync -a --info=progress2 "$rootfs/" "$mnt/" 2>/dev/null || cp -a "$rootfs"/* "$mnt/"
        
        # 4. Configure mirror
        echo "Server = ${MIRROR_ARCH}/\$repo/os/\$arch" > "$mnt/etc/pacman.d/mirrorlist"
    fi
    
    # 5. Chroot install
    prepare_chroot "$mnt"
    
    info "Installing base system and kernel..."
    case "$initramfs_method" in
        dracut)
            run_chroot "$mnt" pacman -Sy --noconfirm base base-devel linux linux-firmware \
                dracut kpartx multipath-tools ntfs-3g util-linux lvm2 2>/dev/null || \
            run_chroot "$mnt" pacman -Sy --noconfirm base base-devel linux linux-firmware \
                dracut kpartx ntfs-3g util-linux
            ;;
        mkinitcpio)
            run_chroot "$mnt" pacman -Sy --noconfirm base base-devel linux linux-firmware \
                mkinitcpio kpartx multipath-tools ntfs-3g util-linux lvm2 2>/dev/null || \
            run_chroot "$mnt" pacman -Sy --noconfirm base base-devel linux linux-firmware \
                mkinitcpio kpartx ntfs-3g util-linux
            ;;
        *) run_chroot "$mnt" pacman -Sy --noconfirm base base-devel linux linux-firmware \
            dracut kpartx ntfs-3g util-linux ;;
    esac
    
    # 6. Configure system
    echo "arch-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "en_US.UTF-8 UTF-8" >> "$mnt/etc/locale.gen"
    echo "zh_CN.UTF-8 UTF-8" >> "$mnt/etc/locale.gen"
    run_chroot "$mnt" locale-gen 2>/dev/null || true
    echo 'LANG=en_US.UTF-8' > "$mnt/etc/locale.conf"
    
    # Generate fstab, set root password, configure network
    generate_fstab "$mnt" "$loop_dev"
    setup_root_password "$mnt"
    setup_network "$mnt"
    
    # Enable essential services
    run_chroot "$mnt" systemctl enable systemd-networkd 2>/dev/null || true
    run_chroot "$mnt" systemctl enable systemd-resolved 2>/dev/null || true
    
    # 7. Build vhdboot initramfs
    build_initramfs "$mnt" "$boot_mode" "$initramfs_method"
    
    # 8. Configure GRUB (internal boot support)
    run_chroot "$mnt" pacman -S --noconfirm grub efibootmgr 2>/dev/null || true
    
    cleanup_chroot "$mnt"
    copy_boot_files_to_output "$mnt" "$output"
    
    # SquashFS: create from mounted rootfs before unmount
    if [ "$fmt" = "squashfs" ]; then
        check_squashfs_deps
        mkdir -p "$(dirname "$output")"
        create_squashfs "$mnt" "$output"
    fi
    
    unmount_disk "$mnt" "$loop_dev"
    
    # Convert format (skip for squashfs, already created above)
    if [ "$fmt" != "squashfs" ]; then
        mkdir -p "$(dirname "$output")"
        case "$fmt" in
            vhd)
                local subformat="dynamic"
                [ "$disk_type" = "fixed" ] && subformat="fixed"
                qemu-img convert -f raw -O vpc -o subformat=${subformat} "$raw_disk" "$output"
                ;;
            vmdk)  qemu-img convert -f raw -O vmdk "$raw_disk" "$output" ;;
            vdi)   qemu-img convert -f raw -O vdi "$raw_disk" "$output" ;;
            qcow2)
                local prealloc="off"
                [ "$disk_type" = "fixed" ] && prealloc="full"
                qemu-img convert -f raw -O qcow2 -o preallocation=${prealloc} "$raw_disk" "$output"
                ;;
            vhdx)
                local subformat="dynamic"
                [ "$disk_type" = "fixed" ] && subformat="fixed"
                qemu-img convert -f raw -O vhdx -o subformat=${subformat} "$raw_disk" "$output"
                ;;
            *)     cp "$raw_disk" "$output" ;;
        esac
    fi
    
    clear_cleanup_trap
    rm -rf "$workdir"
    info "Build complete: $output"
}

build "$@"
