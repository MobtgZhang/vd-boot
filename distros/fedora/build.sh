#!/bin/bash
# Fedora - Build bootable VHD from Tsinghua mirror via dnf

set -e
REBUILD2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REBUILD2_ROOT/lib/common.sh"
source "$REBUILD2_ROOT/lib/disk.sh"
source "$REBUILD2_ROOT/lib/chroot.sh"
[ -f "$REBUILD2_ROOT/config/mirrors.conf" ] && source "$REBUILD2_ROOT/config/mirrors.conf"

build() {
    local output="$1" size="${2:-16}" disk_type="${3:-dynamic}" boot_mode="${4:-kloop}" fmt="${5:-vhd}" initramfs_method="${6:-}"
    [ -z "$initramfs_method" ] && initramfs_method="$(get_initramfs_default fedora)"
    
    check_root
    check_deps
    
    command -v dnf >/dev/null || err "Please install dnf: apt install dnf or use Fedora system"
    
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    local mnt="$workdir/mnt"
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/fedora.raw"
    info "Creating disk ${size}GB ($disk_type)..."
    create_disk "$raw_disk" "$size" "$disk_type" "raw"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    # If system already installed in partition, skip dnf install
    if [ -f "$mnt/etc/os-release" ]; then
        info "Detected installed system, skipping dnf install..."
    else
        # dnf --installroot, using Tsinghua mirror
        info "dnf install from $MIRROR_FEDORA (release $FEDORA_RELEASE)..."
        mkdir -p "$mnt/etc/yum.repos.d"
        cat > "$mnt/etc/yum.repos.d/fedora.repo" << EOF
[fedora]
name=Fedora
baseurl=${MIRROR_FEDORA}/releases/$FEDORA_RELEASE/Everything/x86_64/os/
enabled=1
gpgcheck=0
metadata_expire=7d
[updates]
name=Fedora Updates
baseurl=${MIRROR_FEDORA}/updates/$FEDORA_RELEASE/Everything/x86_64/
enabled=1
gpgcheck=0
metadata_expire=6h
EOF
        
        dnf --installroot="$mnt" --releasever="$FEDORA_RELEASE" --setopt=reposdir="$mnt/etc/yum.repos.d" \
            install -y @core kernel coreutils dracut kpartx ntfs-3g util-linux lvm2 2>/dev/null || \
        dnf --installroot="$mnt" --releasever="$FEDORA_RELEASE" install -y @core kernel coreutils dracut kpartx ntfs-3g util-linux lvm2 \
            --repofrompath=fedora,${MIRROR_FEDORA}/releases/$FEDORA_RELEASE/Everything/x86_64/os/ \
            --repofrompath=updates,${MIRROR_FEDORA}/updates/$FEDORA_RELEASE/Everything/x86_64/
    fi
    
    prepare_chroot "$mnt"
    
    echo "fedora-vhd" > "$mnt/etc/hostname"
    run_chroot "$mnt" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    
    # Fedora default is dracut, install if mkinitramfs selected
    [ "$initramfs_method" = "mkinitramfs" ] && \
        run_chroot "$mnt" dnf install -y initramfs-tools 2>/dev/null || true
    
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
