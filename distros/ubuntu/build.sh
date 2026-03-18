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
    local loop_dev=""
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/ubuntu.raw"
    info "Creating disk ${size}GB..."
    truncate -s "${size}G" "$raw_disk"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    setup_cleanup_trap "$mnt" "$loop_dev" "$workdir"
    
    if [ -f "$mnt/etc/os-release" ] || [ -f "$mnt/etc/debian_version" ]; then
        info "Detected installed system, skipping debootstrap..."
    else
        info "debootstrap from $MIRROR_UBUNTU (${UBUNTU_CODENAME})..."
        LANG=C.UTF-8 LC_ALL=C.UTF-8 debootstrap --arch=amd64 "$UBUNTU_CODENAME" "$mnt" "$MIRROR_UBUNTU"
        
        cat > "$mnt/etc/apt/sources.list" << EOF
deb ${MIRROR_UBUNTU} ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${MIRROR_UBUNTU} ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb ${MIRROR_UBUNTU} ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF
    fi
    
    prepare_chroot "$mnt"
    
    # Wrap uname -r to return chroot kernel version (host uname returns host kernel)
    if [ -f "$mnt/usr/bin/uname" ]; then
        cp "$mnt/usr/bin/uname" "$mnt/usr/bin/uname.real"
        cat > "$mnt/usr/local/bin/uname" << 'UNAME_WRAPPER'
#!/bin/sh
if [ "$1" = "-r" ]; then
    ls /lib/modules 2>/dev/null | sort -V | tail -1 || /usr/bin/uname.real -r
else
    exec /usr/bin/uname.real "$@"
fi
UNAME_WRAPPER
        chmod +x "$mnt/usr/local/bin/uname"
    fi
    
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
    
    echo "ubuntu-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "en_US.UTF-8 UTF-8" >> "$mnt/etc/locale.gen"
    echo "zh_CN.UTF-8 UTF-8" >> "$mnt/etc/locale.gen"
    run_chroot "$mnt" locale-gen 2>/dev/null || true
    
    # Generate fstab, set root password, configure network
    generate_fstab "$mnt" "$loop_dev"
    setup_root_password "$mnt"
    setup_network "$mnt"
    
    # Build initramfs
    build_initramfs "$mnt" "$boot_mode" "$initramfs_method"
    
    # Copy vmlinuz to standard location
    run_chroot "$mnt" bash -c 'K=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1); [ -n "$K" ] && cp "$K" /boot/vmlinuz-vhdboot'
    
    # Cleanup uname wrapper
    rm -f "$mnt/usr/local/bin/uname" "$mnt/usr/bin/uname.real" 2>/dev/null || true
    
    cleanup_chroot "$mnt"
    copy_boot_files_to_output "$mnt" "$output"
    
    if [ "$fmt" = "squashfs" ]; then
        check_squashfs_deps
        mkdir -p "$(dirname "$output")"
        create_squashfs "$mnt" "$output"
    fi
    
    unmount_disk "$mnt" "$loop_dev"
    
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
