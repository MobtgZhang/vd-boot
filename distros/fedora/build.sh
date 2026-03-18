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
    local loop_dev=""
    
    mkdir -p "$workdir" "$mnt"
    
    local raw_disk="$workdir/fedora.raw"
    info "Creating disk ${size}GB..."
    truncate -s "${size}G" "$raw_disk"
    
    info "Partitioning and mounting..."
    loop_dev=$(partition_and_mount "$raw_disk" "$mnt")
    
    setup_cleanup_trap "$mnt" "$loop_dev" "$workdir"
    
    if [ -f "$mnt/etc/os-release" ]; then
        info "Detected installed system, skipping dnf install..."
    else
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
    echo "en_US.UTF-8 UTF-8" >> "$mnt/etc/locale.gen" 2>/dev/null || true
    run_chroot "$mnt" localedef -i en_US -f UTF-8 en_US.UTF-8 2>/dev/null || true
    
    # Fedora default is dracut, install initramfs-tools if mkinitramfs selected
    [ "$initramfs_method" = "mkinitramfs" ] && \
        run_chroot "$mnt" dnf install -y initramfs-tools 2>/dev/null || true
    
    # Generate fstab, set root password, configure network
    generate_fstab "$mnt" "$loop_dev"
    setup_root_password "$mnt"
    setup_network "$mnt"
    
    # Enable essential services
    run_chroot "$mnt" systemctl enable systemd-networkd 2>/dev/null || true
    run_chroot "$mnt" systemctl enable systemd-resolved 2>/dev/null || true
    
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
