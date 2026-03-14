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
    
    command -v zypper >/dev/null || err "OpenSUSE build requires zypper, run on OpenSUSE host or use: docker run --privileged -v \$(pwd):/out opensuse/leap /out/vd-boot/distros/opensuse/build.sh ..."
    
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    local mnt="$workdir/mnt"
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/opensuse.raw"
    info "Creating disk ${size}GB ($disk_type)..."
    create_disk "$raw_disk" "$size" "$disk_type" "raw"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    # If system already installed in partition, skip zypper install
    if [ -f "$mnt/etc/os-release" ]; then
        info "Detected installed system, skipping zypper install..."
    else
        # Configure zypper repos
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
        
        # zypper --root install
        info "zypper install (Leap ${OPENSUSE_LEAP})..."
        zypper --root="$mnt" --non-interactive refresh 2>/dev/null || true
        zypper --root="$mnt" --non-interactive install -y -t pattern minimal_base 2>/dev/null || \
        zypper --root="$mnt" --non-interactive install -y aaa_base kernel-default dracut kpartx ntfs-3g util-linux lvm2
        
        # If pattern install fails, try direct package install
        if [ ! -f "$mnt/usr/bin/bash" ]; then
            zypper --root="$mnt" --non-interactive install -y aaa_base filesystem bash coreutils kernel-default dracut kpartx ntfs-3g util-linux lvm2
        fi
    fi
    
    echo "opensuse-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
    
    prepare_chroot "$mnt"
    
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
