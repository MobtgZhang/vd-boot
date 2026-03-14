#!/bin/bash
# Disk creation: fixed/dynamic size, VHD/VMDK/VDI format

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

create_disk() {
    local output="$1"
    local size_gb="${2:-16}"
    local disk_type="${3:-dynamic}"
    local fmt=""
    
    [ -z "$output" ] && err "Output path not specified"
    
    case "$output" in
        *.vhd) fmt="vpc" ;;
        *.vmdk) fmt="vmdk" ;;
        *.vdi) fmt="vdi" ;;
        *.img|*.raw) fmt="raw" ;;
        *) fmt="raw"; output="${output}.img" ;;
    esac
    
    mkdir -p "$(dirname "$output")"
    if [ -f "$output" ] && [ -s "$output" ]; then
        info "Disk already exists, skipping creation: $output"
        echo "$output"
        return
    fi
    rm -f "$output"
    
    case "$fmt" in
        vpc)
            [ "$disk_type" = "fixed" ] && opts="-o subformat=fixed" || opts="-o subformat=dynamic"
            qemu-img create -f vpc $opts "$output" "${size_gb}G"
            ;;
        vmdk)
            [ "$disk_type" = "fixed" ] && opts="-o subformat=full" || opts="-o subformat=streamOptimized"
            qemu-img create -f vmdk $opts "$output" "${size_gb}G"
            ;;
        vdi)
            [ "$disk_type" = "fixed" ] && opts="-o static" || opts=""
            qemu-img create -f vdi $opts "$output" "${size_gb}G"
            ;;
        raw)
            truncate -s "${size_gb}G" "$output"
            ;;
        *) err "Unsupported format" ;;
    esac
    
    echo "$output"
}

# Partition and format, return loop device name
# If disk already has ext4 partition, only mount, do not repartition
partition_and_mount() {
    local disk="$1" mnt="$2"
    [ -f "$disk" ] || err "Disk does not exist: $disk"
    mkdir -p "$mnt"
    
    local loop_dev=$(losetup -f)
    losetup -P "$loop_dev" "$disk" 2>/dev/null || losetup "$loop_dev" "$disk"
    
    partprobe "$loop_dev" 2>/dev/null
    sleep 1
    
    local part="${loop_dev}p1"
    [ -b "$part" ] || part="${loop_dev}1"
    [ -b "$part" ] || sleep 2
    
    # If partition exists and is ext4, only mount
    if [ -b "$part" ] && blkid "$part" 2>/dev/null | grep -q 'TYPE="ext4"'; then
        info "Partition exists, mounting only..."
        mount "$part" "$mnt"
        echo "$loop_dev"
        return
    fi
    
    # No partition or not ext4, partition and format
    parted -s "$loop_dev" mklabel gpt mkpart primary ext4 1MiB 100% set 1 boot on
    partprobe "$loop_dev" 2>/dev/null
    sleep 1
    
    part="${loop_dev}p1"
    [ -b "$part" ] || part="${loop_dev}1"
    [ -b "$part" ] || sleep 2
    
    mkfs.ext4 -F -L rootfs "$part"
    mount "$part" "$mnt"
    
    echo "$loop_dev"
}

unmount_disk() {
    local mnt="$1" loop_dev="$2"
    umount -R "$mnt" 2>/dev/null || true
    [ -n "$loop_dev" ] && losetup -d "$loop_dev" 2>/dev/null || true
}

# Convert format: raw -> vhd/vmdk/vdi
convert_format() {
    local src="$1" dst="$2"
    [ -f "$src" ] || err "Source does not exist: $src"
    local ofmt=""
    case "$dst" in
        *.vhd) ofmt="vpc" ;;
        *.vmdk) ofmt="vmdk" ;;
        *.vdi) ofmt="vdi" ;;
        *) err "Unsupported output format" ;;
    esac
    qemu-img convert -f raw -O "$ofmt" "$src" "$dst"
}
