#!/bin/bash
# Ubuntu - Build bootable VHD from Tsinghua mirror via debootstrap

set -e
REBUILD2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REBUILD2_ROOT/lib/common.sh"
source "$REBUILD2_ROOT/lib/disk.sh"
source "$REBUILD2_ROOT/lib/chroot.sh"
[ -f "$REBUILD2_ROOT/config/mirrors.conf" ] && source "$REBUILD2_ROOT/config/mirrors.conf"

build() {
    local output="$1" size="${2:-16}" disk_type="${3:-dynamic}" boot_mode="${4:-kloop}" fmt="${5:-vhd}" initramfs_method="${6:-}"
    [ -z "$initramfs_method" ] && initramfs_method="$(get_initramfs_default ubuntu)"
    
    check_root
    check_deps
    
    command -v debootstrap >/dev/null || err "Please install debootstrap: apt install debootstrap"
    
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    local mnt="$workdir/mnt"
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/ubuntu.raw"
    info "Creating disk ${size}GB ($disk_type)..."
    create_disk "$raw_disk" "$size" "$disk_type" "raw"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    # If system already installed in partition, skip debootstrap
    if [ -f "$mnt/etc/os-release" ] || [ -f "$mnt/etc/debian_version" ]; then
        info "Detected installed system, skipping debootstrap..."
    else
        info "debootstrap from $MIRROR_UBUNTU (${UBUNTU_CODENAME})..."
        LANG=C.UTF-8 LC_ALL=C.UTF-8 debootstrap --arch=amd64 "$UBUNTU_CODENAME" "$mnt" "$MIRROR_UBUNTU"
        
        # Configure sources
        cat > "$mnt/etc/apt/sources.list" << EOF
deb ${MIRROR_UBUNTU} ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${MIRROR_UBUNTU} ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb ${MIRROR_UBUNTU} ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF
    fi
    
    prepare_chroot "$mnt"
    
    # In chroot uname -r returns host kernel, causing dracut to miss /lib/modules/<host-version>/, create wrapper to return chroot kernel version
    mkdir -p "$mnt/usr/local/bin"
    cp "$mnt/usr/bin/uname" "$mnt/usr/bin/uname.real"
    cat > "$mnt/usr/local/bin/uname" << 'UNAME_WRAPPER'
#!/bin/sh
if [ "$1" = "-r" ]; then
    ls /lib/modules 2>/dev/null | head -1 || /usr/bin/uname.real -r
else
    exec /usr/bin/uname.real "$@"
fi
UNAME_WRAPPER
    chmod +x "$mnt/usr/local/bin/uname"
    
    # Install kernel and tools (per initramfs method)
    info "Installing kernel and $initramfs_method related packages..."
    run_chroot "$mnt" apt-get update
    case "$initramfs_method" in
        dracut)
            run_chroot "$mnt" apt-get install -y linux-generic dracut kpartx ntfs-3g util-linux lvm2
            ;;
        mkinitramfs)
            run_chroot "$mnt" apt-get install -y linux-generic initramfs-tools kpartx ntfs-3g util-linux lvm2
            ;;
        *) run_chroot "$mnt" apt-get install -y linux-generic dracut kpartx ntfs-3g util-linux lvm2 ;;
    esac
    
    # Configure
    echo "ubuntu-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    
    # Build initramfs
    build_initramfs "$mnt" "$boot_mode" "$initramfs_method"
    
    # Copy vmlinuz to standard location
    run_chroot "$mnt" bash -c 'K=$(ls /boot/vmlinuz-* 2>/dev/null | head -1); [ -n "$K" ] && cp "$K" /boot/vmlinuz-vhdboot'
    
    cleanup_chroot "$mnt"
    copy_boot_files_to_output "$mnt" "$output"
    unmount_disk "$mnt" "$loop_dev"
    
    # Convert
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
