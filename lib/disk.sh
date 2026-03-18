#!/bin/bash
# Disk creation: fixed/dynamic size, VHD/VMDK/VDI/QCOW2/VHDX/SquashFS format

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
        *.qcow2) fmt="qcow2" ;;
        *.vhdx) fmt="vhdx" ;;
        *.squashfs) fmt="squashfs" ;;
        *.img|*.raw) fmt="raw" ;;
        *) fmt="raw"; output="${output}.img" ;;
    esac

    # SquashFS is built from rootfs directory, not pre-created
    if [ "$fmt" = "squashfs" ]; then
        echo "$output"
        return
    fi
    
    mkdir -p "$(dirname "$output")"
    if [ -f "$output" ] && [ -s "$output" ]; then
        info "Disk already exists, skipping creation: $output"
        echo "$output"
        return
    fi
    rm -f "$output"
    
    local opts=""
    case "$fmt" in
        vpc)
            [ "$disk_type" = "fixed" ] && opts="-o subformat=fixed" || opts="-o subformat=dynamic"
            qemu-img create -f vpc $opts "$output" "${size_gb}G"
            ;;
        vmdk)
            [ "$disk_type" = "fixed" ] && opts="-o subformat=monolithicFlat" || opts="-o subformat=monolithicSparse"
            qemu-img create -f vmdk $opts "$output" "${size_gb}G"
            ;;
        vdi)
            [ "$disk_type" = "fixed" ] && opts="-o static=on" || opts=""
            qemu-img create -f vdi $opts "$output" "${size_gb}G"
            ;;
        qcow2)
            [ "$disk_type" = "fixed" ] && opts="-o preallocation=full" || opts="-o preallocation=off"
            qemu-img create -f qcow2 $opts "$output" "${size_gb}G"
            ;;
        vhdx)
            [ "$disk_type" = "fixed" ] && opts="-o subformat=fixed" || opts="-o subformat=dynamic"
            qemu-img create -f vhdx $opts "$output" "${size_gb}G"
            ;;
        raw)
            truncate -s "${size_gb}G" "$output"
            ;;
        *) err "Unsupported format: $fmt" ;;
    esac
    
    echo "$output"
}

# Partition and format, return loop device name
# If disk already has ext4 partition, only mount, do not repartition
partition_and_mount() {
    local disk="$1" mnt="$2"
    [ -f "$disk" ] || err "Disk does not exist: $disk"
    mkdir -p "$mnt"
    
    local loop_dev
    loop_dev=$(losetup -f)
    losetup -P "$loop_dev" "$disk" 2>/dev/null || losetup "$loop_dev" "$disk"
    debug "Attached loop device: $loop_dev -> $disk"
    
    partprobe "$loop_dev" 2>/dev/null || true
    sleep 1
    
    local part="${loop_dev}p1"
    [ -b "$part" ] || part="${loop_dev}1"
    [ -b "$part" ] || sleep 2
    
    # If partition exists and is ext4, only mount
    if [ -b "$part" ] && blkid "$part" 2>/dev/null | grep -q 'TYPE="ext4"'; then
        info "Existing ext4 partition detected, mounting..."
        mount "$part" "$mnt"
        echo "$loop_dev"
        return
    fi
    
    # Create GPT partition table with single ext4 partition
    info "Creating GPT partition table..."
    parted -s "$loop_dev" mklabel gpt mkpart primary ext4 1MiB 100% set 1 boot on
    partprobe "$loop_dev" 2>/dev/null || true
    sleep 1
    
    part="${loop_dev}p1"
    [ -b "$part" ] || part="${loop_dev}1"
    # Wait for partition device to appear
    local retries=5
    while [ ! -b "$part" ] && [ $retries -gt 0 ]; do
        sleep 1
        retries=$((retries - 1))
    done
    [ -b "$part" ] || err "Partition device $part not found after partitioning"
    
    info "Formatting ext4..."
    mkfs.ext4 -F -L rootfs "$part"
    mount "$part" "$mnt"
    
    echo "$loop_dev"
}

unmount_disk() {
    local mnt="$1" loop_dev="$2"
    sync
    umount -R "$mnt" 2>/dev/null || true
    sleep 1
    [ -n "$loop_dev" ] && losetup -d "$loop_dev" 2>/dev/null || true
}

# Convert format: raw -> vhd/vmdk/vdi/qcow2/vhdx with disk_type support
convert_format() {
    local src="$1" dst="$2" disk_type="${3:-dynamic}"
    [ -f "$src" ] || err "Source does not exist: $src"
    
    local ofmt="" opts=""
    case "$dst" in
        *.vhd)
            ofmt="vpc"
            [ "$disk_type" = "fixed" ] && opts="-o subformat=fixed" || opts="-o subformat=dynamic"
            ;;
        *.vmdk)
            ofmt="vmdk"
            [ "$disk_type" = "fixed" ] && opts="-o subformat=monolithicFlat" || opts="-o subformat=monolithicSparse"
            ;;
        *.vdi)
            ofmt="vdi"
            [ "$disk_type" = "fixed" ] && opts="-o static=on" || opts=""
            ;;
        *.qcow2)
            ofmt="qcow2"
            [ "$disk_type" = "fixed" ] && opts="-o preallocation=full" || opts="-o preallocation=off"
            ;;
        *.vhdx)
            ofmt="vhdx"
            [ "$disk_type" = "fixed" ] && opts="-o subformat=fixed" || opts="-o subformat=dynamic"
            ;;
        *) err "Unsupported output format: $dst" ;;
    esac
    
    info "Converting $src -> $dst ($ofmt, $disk_type)..."
    qemu-img convert -f raw -O "$ofmt" $opts "$src" "$dst"
}

# Create SquashFS image from a mounted rootfs directory
create_squashfs() {
    local rootfs_dir="$1" output="$2"
    [ -d "$rootfs_dir" ] || err "Root filesystem directory does not exist: $rootfs_dir"
    
    command -v mksquashfs >/dev/null 2>&1 || err "mksquashfs not found. Install: apt install squashfs-tools"
    
    info "Creating SquashFS image from $rootfs_dir..."
    mksquashfs "$rootfs_dir" "$output" -comp xz -b 1M -Xdict-size 100% -noappend \
        -e proc sys dev run tmp
    
    local size
    size=$(du -h "$output" | cut -f1)
    info "SquashFS image created: $output ($size)"
}
