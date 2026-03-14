#!/bin/bash
# Deepin - Build bootable VHD from Tsinghua mirror via debootstrap (Debian-based)

set -e
REBUILD2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REBUILD2_ROOT/lib/common.sh"
source "$REBUILD2_ROOT/lib/disk.sh"
source "$REBUILD2_ROOT/lib/chroot.sh"
[ -f "$REBUILD2_ROOT/config/mirrors.conf" ] && source "$REBUILD2_ROOT/config/mirrors.conf"

build() {
    local output="$1" size="${2:-16}" disk_type="${3:-dynamic}" boot_mode="${4:-kloop}" fmt="${5:-vhd}" initramfs_method="${6:-}"
    [ -z "$initramfs_method" ] && initramfs_method="$(get_initramfs_default deepin)"
    
    check_root
    check_deps
    
    command -v debootstrap >/dev/null || err "Please install debootstrap: apt install debootstrap"
    
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    local mnt="$workdir/mnt"
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/deepin.raw"
    info "Creating disk ${size}GB ($disk_type)..."
    create_disk "$raw_disk" "$size" "$disk_type" "raw"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    # If system already installed in partition, skip debootstrap
    if [ -f "$mnt/etc/os-release" ] || [ -f "$mnt/etc/debian_version" ]; then
        info "Detected installed system, skipping debootstrap..."
    else
        # Deepin is Debian-based, use Debian bookworm as base when no deepin debootstrap script
        info "debootstrap (Deepin based on Debian)..."
        LANG=C.UTF-8 LC_ALL=C.UTF-8 debootstrap --arch=amd64 bookworm "$mnt" "${MIRROR_DEBIAN:-https://mirrors.tuna.tsinghua.edu.cn/debian}"
        
        # Prefer Deepin mirror, fallback to Debian if unavailable
        if curl -sI "${MIRROR_DEEPIN}/dists/${DEEPIN_CODENAME}/Release" | head -1 | grep -q 200; then
            cat > "$mnt/etc/apt/sources.list" << EOF
deb ${MIRROR_DEEPIN} ${DEEPIN_CODENAME} main contrib non-free
deb ${MIRROR_DEEPIN} ${DEEPIN_CODENAME}-updates main contrib non-free
EOF
        else
            cat > "$mnt/etc/apt/sources.list" << EOF
deb ${MIRROR_DEBIAN} bookworm main contrib non-free non-free-firmware
deb ${MIRROR_DEBIAN} bookworm-updates main contrib non-free non-free-firmware
EOF
            warn "Deepin ${DEEPIN_CODENAME} mirror unavailable, using Debian bookworm"
        fi
    fi
    
    prepare_chroot "$mnt"
    
    info "Installing kernel and $initramfs_method related packages..."
    run_chroot "$mnt" apt-get update
    case "$initramfs_method" in
        dracut)
            run_chroot "$mnt" apt-get install -y linux-image-amd64 dracut kpartx ntfs-3g util-linux lvm2 2>/dev/null || \
            run_chroot "$mnt" apt-get install -y linux-image-amd64 kpartx ntfs-3g util-linux lvm2
            run_chroot "$mnt" apt-get install -y dracut 2>/dev/null || true
            ;;
        mkinitramfs)
            run_chroot "$mnt" apt-get install -y linux-image-amd64 initramfs-tools kpartx ntfs-3g util-linux lvm2 2>/dev/null || \
            run_chroot "$mnt" apt-get install -y linux-image-amd64 kpartx ntfs-3g util-linux lvm2
            ;;
        *) run_chroot "$mnt" apt-get install -y linux-image-amd64 dracut kpartx ntfs-3g util-linux lvm2 2>/dev/null || true ;;
    esac
    
    echo "deepin-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    
    build_initramfs "$mnt" "$boot_mode" "$initramfs_method"
    
    cleanup_chroot "$mnt"
    copy_boot_files_to_output "$mnt" "$output"
    unmount_disk "$mnt" "$loop_dev"
    
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
