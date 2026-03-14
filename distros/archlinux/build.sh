#!/bin/bash
# Arch Linux - Build bootable VHD from Tsinghua mirror

set -e
REBUILD2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REBUILD2_ROOT/lib/common.sh"
source "$REBUILD2_ROOT/lib/disk.sh"
source "$REBUILD2_ROOT/lib/chroot.sh"
[ -f "$REBUILD2_ROOT/config/mirrors.conf" ] && source "$REBUILD2_ROOT/config/mirrors.conf"

# Args: $1=output path $2=size(GB) $3=fixed|dynamic $4=kloop|vloop $5=format $6=initramfs method
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
    
    mkdir -p "$workdir" "$mnt"
    
    # 1. Create disk (build with raw first, convert at end)
    local raw_disk="$workdir/arch.raw"
    info "Creating disk ${size}GB ($disk_type)..."
    create_disk "$raw_disk" "$size" "$disk_type" "raw"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    # If system already installed in partition, skip bootstrap
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
        [ -d "$rootfs" ] || err "root directory not found"
        
        # Move root contents to mnt
        rsync -a --info=progress2 "$rootfs/" "$mnt/" 2>/dev/null || cp -a "$rootfs"/* "$mnt/"
        
        # 4. Configure mirror
        echo "Server = ${MIRROR_ARCH}/\$repo/os/\$arch" > "$mnt/etc/pacman.d/mirrorlist"
    fi
    
    # 5. Chroot install
    prepare_chroot "$mnt"
    
    info "Installing base and kernel..."
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
    run_chroot "$mnt" locale-gen 2>/dev/null || true
    
    # 7. Build vhdboot initramfs
    build_initramfs "$mnt" "$boot_mode" "$initramfs_method"
    
    # 8. Configure GRUB
    run_chroot "$mnt" pacman -S --noconfirm grub efibootmgr 2>/dev/null || true
    if [ -d "$mnt/boot/efi" ] || [ -d "$mnt/efi" ]; then
        run_chroot "$mnt" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch 2>/dev/null || \
        run_chroot "$mnt" grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=arch 2>/dev/null || true
    fi
    
    # Use initramfs-vhdboot as default
    run_chroot "$mnt" bash -c 'cat > /etc/default/grub.d/vhdboot.cfg << EOF
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT="root=UUID=ROOTUUID kloop=/vhd/arch.vhd kroot=/dev/mapper/loop0p1"
EOF' 2>/dev/null || true
    
    cleanup_chroot "$mnt"
    copy_boot_files_to_output "$mnt" "$output"
    unmount_disk "$mnt" "$loop_dev"
    
    # 9. Convert format
    mkdir -p "$(dirname "$output")"
    case "$fmt" in
        vhd) qemu-img convert -f raw -O vpc -o subformat=${disk_type} "$raw_disk" "$output" ;;
        vmdk) qemu-img convert -f raw -O vmdk "$raw_disk" "$output" ;;
        vdi) qemu-img convert -f raw -O vdi "$raw_disk" "$output" ;;
        *) cp "$raw_disk" "$output" ;;
    esac
    
    rm -rf "$workdir"
    info "Done: $output"
}

build "$@"
