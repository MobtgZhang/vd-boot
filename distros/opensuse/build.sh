#!/bin/bash
# OpenSUSE Leap - Build bootable VHD from Tsinghua mirror
# Must run on OpenSUSE host, or use Docker container

set -e
REBUILD2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REBUILD2_ROOT/lib/common.sh"
source "$REBUILD2_ROOT/lib/disk.sh"
source "$REBUILD2_ROOT/lib/chroot.sh"
[ -f "$REBUILD2_ROOT/config/mirrors.conf" ] && source "$REBUILD2_ROOT/config/mirrors.conf"

build() {
    local output="$1" size="${2:-16}" disk_type="${3:-dynamic}" boot_mode="${4:-kloop}" fmt="${5:-vhd}" initramfs_method="${6:-}"
    [ -z "$initramfs_method" ] && initramfs_method="$(get_initramfs_default opensuse)"
    
    check_root
    check_deps
    
    command -v zypper >/dev/null || err "OpenSUSE build requires zypper, run on OpenSUSE host or use:\n  docker run --privileged -v \$(pwd):/out opensuse/leap /out/vd-boot/distros/opensuse/build.sh ..."
    
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    local mnt="$workdir/mnt"
    local loop_dev=""
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/opensuse.raw"
    info "Creating disk ${size}GB..."
    truncate -s "${size}G" "$raw_disk"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    setup_cleanup_trap "$mnt" "$loop_dev" "$workdir"
    
    if [ -f "$mnt/etc/os-release" ]; then
        info "Detected installed system, skipping zypper install..."
    else
        mkdir -p "$mnt/etc/zypp/repos.d"
        cat > "$mnt/etc/zypp/repos.d/oss.repo" << EOF
[oss]
name=OSS
baseurl=${MIRROR_OPENSUSE}/distribution/leap/${OPENSUSE_LEAP}/repo/oss/
enabled=1
gpgcheck=0
EOF
        cat > "$mnt/etc/zypp/repos.d/update.repo" << EOF
[update]
name=Update
baseurl=${MIRROR_OPENSUSE}/update/leap/${OPENSUSE_LEAP}/oss/
enabled=1
gpgcheck=0
EOF
        
        info "zypper install (Leap ${OPENSUSE_LEAP})..."
        zypper --root="$mnt" --non-interactive refresh 2>/dev/null || true
        zypper --root="$mnt" --non-interactive install -y -t pattern minimal_base 2>/dev/null || \
        zypper --root="$mnt" --non-interactive install -y aaa_base kernel-default dracut kpartx ntfs-3g util-linux lvm2
        
        if [ ! -f "$mnt/usr/bin/bash" ]; then
            zypper --root="$mnt" --non-interactive install -y aaa_base filesystem bash coreutils kernel-default dracut kpartx ntfs-3g util-linux lvm2
        fi
    fi
    
    echo "opensuse-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
    
    prepare_chroot "$mnt"
    
    # Generate fstab, set root password, configure network
    generate_fstab "$mnt" "$loop_dev"
    setup_root_password "$mnt"
    setup_network "$mnt"
    
    # Enable essential services
    run_chroot "$mnt" systemctl enable systemd-networkd 2>/dev/null || true
    run_chroot "$mnt" systemctl enable systemd-resolved 2>/dev/null || true
    run_chroot "$mnt" systemctl enable wicked 2>/dev/null || true
    
    build_initramfs "$mnt" "$boot_mode" "$initramfs_method"
    
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
