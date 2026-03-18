#!/bin/bash
#
# vd-boot - Build bootable VHD/VMDK/VDI/QCOW2/VHDX/SquashFS from Tsinghua mirror
# Distributions: archlinux, ubuntu, fedora, debian, deepin, opensuse
# Boot modes: kloop, vloop
# Disk types: fixed, dynamic
# Formats: vhd, vmdk, vdi, qcow2, vhdx, squashfs
#

set -e

RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUN_DIR/lib/common.sh"

OUTPUT_DIR="${OUTPUT_DIR:-$RUN_DIR/output}"
MIRROR_TSINGHUA="https://mirrors.tuna.tsinghua.edu.cn"

DISTROS="archlinux ubuntu fedora debian deepin opensuse"
BOOT_MODES="kloop vloop"
DISK_TYPES="fixed dynamic"
FORMATS="vhd vmdk vdi qcow2 vhdx squashfs"
INITRAMFS_METHODS="dracut mkinitramfs mkinitcpio"

usage() {
    cat << EOF
vd-boot v${VD_BOOT_VERSION} - Build bootable virtual disks from Tsinghua mirror

Usage: $0 <command> [arguments]

Commands:
  build <distribution> [options]  Build single image
     Distribution: archlinux | ubuntu | fedora | debian | deepin | opensuse
     Options:
       -o, --output PATH   Output path (default: output/<distro>-<boot>-<disk>.<fmt>)
       -s, --size GB      Disk size (default: 16)
       -b, --boot MODE    Boot mode: kloop | vloop (default: kloop)
       -d, --disk TYPE    Disk type: fixed | dynamic (default: dynamic)
       -f, --format FMT   Output format: vhd | vmdk | vdi | qcow2 | vhdx | squashfs (default: vhd)
       -m, --initramfs M  initramfs tool: dracut | mkinitramfs | mkinitcpio (default: per distro)
                          Ubuntu/Debian/Deepin: mkinitramfs, Fedora/OpenSUSE: dracut, Arch: mkinitcpio

  build-all [distribution]  Build all combinations (optional: single distribution)

  qemu <image> [options]    Boot image in QEMU for testing
     Options:
       -m, --memory MB    RAM size (default: 2048)
       -c, --cpus N       CPU count (default: 2)
       -k, --kernel PATH  External kernel (vmlinuz)
       -i, --initrd PATH  External initrd (initramfs-vhdboot.img)
       -a, --append ARGS  Extra kernel cmdline arguments
       -e, --efi          Use UEFI boot (requires OVMF)
       -g, --graphic      Enable graphical display (default: serial console)
       -p, --port N       SSH forward port (default: 2222)

  list                    List supported combinations

  clean                   Clean output directory and temp build files

  version                 Show version

Examples:
  $0 build archlinux -o arch.vhd -b kloop -d fixed
  $0 build ubuntu -s 32 -b vloop -f vmdk -m mkinitramfs
  $0 build fedora -m dracut -d dynamic
  $0 build archlinux -f qcow2 -d dynamic
  $0 build ubuntu -f squashfs
  $0 build-all archlinux
  $0 build-all
  $0 qemu output/archlinux-kloop-dynamic.vhd
  $0 qemu output/archlinux-kloop-dynamic.qcow2 -m 4096 -e
  $0 qemu output/archlinux.squashfs -k output/vmlinuz -i output/initramfs-vhdboot.img
  $0 clean

Environment variables:
  OUTPUT_DIR  Output directory (default: ./output)
  WORKDIR     Build temp directory (default: /tmp/vhdboot-build)
  VD_DEBUG    Set to 1 for debug output

EOF
}

build_one() {
    local distro="$1"
    shift
    local output="" size="16" boot_mode="kloop" disk_type="dynamic" fmt="vhd" initramfs_method=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -o|--output) output="$2"; shift 2 ;;
            -s|--size) size="$2"; shift 2 ;;
            -b|--boot) boot_mode="$2"; shift 2 ;;
            -d|--disk) disk_type="$2"; shift 2 ;;
            -f|--format) fmt="$2"; shift 2 ;;
            -m|--initramfs) initramfs_method="$2"; shift 2 ;;
            *) warn "Unknown option: $1"; shift ;;
        esac
    done

    # Validate inputs
    validate_choice "$distro" "distribution" $DISTROS
    validate_choice "$boot_mode" "boot mode" $BOOT_MODES
    validate_choice "$disk_type" "disk type" $DISK_TYPES
    validate_choice "$fmt" "format" $FORMATS
    [ -n "$initramfs_method" ] && validate_choice "$initramfs_method" "initramfs method" $INITRAMFS_METHODS

    if ! [[ "$size" =~ ^[0-9]+$ ]] || [ "$size" -lt 1 ] || [ "$size" -gt 1024 ]; then
        err "Invalid disk size: '$size' (must be 1-1024 GB)"
    fi
    
    [ -z "$output" ] && output="$OUTPUT_DIR/${distro}-${boot_mode}-${disk_type}.${fmt}"
    if [ -d "$output" ] || [[ "$output" == */ ]]; then
        output="${output%/}/${distro}-${boot_mode}-${disk_type}.${fmt}"
    fi
    
    local build_script="$RUN_DIR/distros/$distro/build.sh"
    [ -f "$build_script" ] || err "Build script not found: $distro"
    
    info "=========================================="
    info "Building $distro"
    info "  Boot mode : $boot_mode"
    info "  Disk type : $disk_type ($fmt)"
    info "  Size      : ${size}GB"
    info "  Output    : $output"
    info "  initramfs : ${initramfs_method:-auto (per distro default)}"
    info "=========================================="
    
    mkdir -p "$(dirname "$output")"
    sudo bash "$build_script" "$output" "$size" "$disk_type" "$boot_mode" "$fmt" "$initramfs_method"
}

build_all() {
    local distro_filter="$1"
    mkdir -p "$OUTPUT_DIR"

    if [ -n "$distro_filter" ]; then
        validate_choice "$distro_filter" "distribution" $DISTROS
    fi
    
    local total=0 success=0 fail=0
    for distro in $DISTROS; do
        [ -n "$distro_filter" ] && [ "$distro" != "$distro_filter" ] && continue
        [ ! -f "$RUN_DIR/distros/$distro/build.sh" ] && continue
        
        for boot in $BOOT_MODES; do
            for disk in $DISK_TYPES; do
                for fmt in vhd; do
                    total=$((total + 1))
                    local out="$OUTPUT_DIR/${distro}-${boot}-${disk}.${fmt}"
                    info "=== [$total] $distro | $boot | $disk | $fmt ==="
                    if build_one "$distro" -o "$out" -b "$boot" -d "$disk" -f "$fmt"; then
                        success=$((success + 1))
                    else
                        fail=$((fail + 1))
                        warn "Build failed: $out"
                    fi
                done
            done
        done
    done
    info "All done. Total: $total, Success: $success, Failed: $fail"
    info "Output directory: $OUTPUT_DIR"
}

qemu_boot() {
    local image="$1"
    shift
    [ -z "$image" ] && err "Missing image path. Usage: $0 qemu <image> [options]"
    [ -f "$image" ] || err "Image not found: $image"

    local memory="2048" cpus="2" kernel="" initrd="" extra_append="" use_efi=0 graphic=0 ssh_port="2222"

    while [ $# -gt 0 ]; do
        case "$1" in
            -m|--memory)  memory="$2"; shift 2 ;;
            -c|--cpus)    cpus="$2"; shift 2 ;;
            -k|--kernel)  kernel="$2"; shift 2 ;;
            -i|--initrd)  initrd="$2"; shift 2 ;;
            -a|--append)  extra_append="$2"; shift 2 ;;
            -e|--efi)     use_efi=1; shift ;;
            -g|--graphic) graphic=1; shift ;;
            -p|--port)    ssh_port="$2"; shift 2 ;;
            *) warn "Unknown qemu option: $1"; shift ;;
        esac
    done

    command -v qemu-system-x86_64 >/dev/null 2>&1 || err "qemu-system-x86_64 not found. Install: apt install qemu-system-x86"

    local qemu_fmt="" drive_opts="" image_dir
    image_dir="$(cd "$(dirname "$image")" && pwd)"
    local image_base="$(basename "$image")"

    case "$image" in
        *.vhd)       qemu_fmt="vpc" ;;
        *.vmdk)      qemu_fmt="vmdk" ;;
        *.vdi)       qemu_fmt="vdi" ;;
        *.qcow2)     qemu_fmt="qcow2" ;;
        *.vhdx)      qemu_fmt="vhdx" ;;
        *.squashfs)  qemu_fmt="squashfs" ;;
        *.img|*.raw) qemu_fmt="raw" ;;
        *)           qemu_fmt="raw" ;;
    esac

    local qemu_args=()
    qemu_args+=(-machine q35,accel=kvm:tcg)
    qemu_args+=(-m "$memory" -smp "$cpus")
    qemu_args+=(-netdev user,id=net0,hostfwd=tcp::"${ssh_port}"-:22)
    qemu_args+=(-device virtio-net-pci,netdev=net0)

    if [ "$graphic" = "0" ]; then
        qemu_args+=(-nographic)
    else
        qemu_args+=(-vga virtio)
    fi

    if [ "$use_efi" = "1" ]; then
        local ovmf=""
        for f in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd \
                 /usr/share/qemu/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd; do
            [ -f "$f" ] && { ovmf="$f"; break; }
        done
        [ -z "$ovmf" ] && err "OVMF firmware not found. Install: apt install ovmf"
        qemu_args+=(-drive if=pflash,format=raw,readonly=on,file="$ovmf")
    fi

    if [ "$qemu_fmt" = "squashfs" ]; then
        if [ -z "$kernel" ]; then
            kernel="$image_dir/vmlinuz"
            [ -f "$kernel" ] || err "SquashFS boot requires external kernel. Use -k/--kernel or place vmlinuz in same directory as image"
        fi
        if [ -z "$initrd" ]; then
            initrd="$image_dir/initramfs-vhdboot.img"
            [ -f "$initrd" ] || err "SquashFS boot requires external initrd. Use -i/--initrd or place initramfs-vhdboot.img in same directory"
        fi

        local tmp_disk="$image_dir/.qemu-squashfs-carrier.raw"
        info "Creating temporary carrier disk for SquashFS..."
        local sqfs_size
        sqfs_size=$(stat -c%s "$image")
        local carrier_mb=$(( (sqfs_size / 1048576) + 128 ))
        truncate -s "${carrier_mb}M" "$tmp_disk"
        mkfs.ext4 -F -q "$tmp_disk"
        local mnt_tmp
        mnt_tmp=$(mktemp -d)
        mount -o loop "$tmp_disk" "$mnt_tmp"
        cp "$image" "$mnt_tmp/rootfs.squashfs"
        umount "$mnt_tmp"
        rmdir "$mnt_tmp"

        qemu_args+=(-drive file="$tmp_disk",format=raw,if=virtio)
        local append="root=/dev/vda squashfs=/rootfs.squashfs console=ttyS0 $extra_append"
        qemu_args+=(-kernel "$kernel" -initrd "$initrd" -append "$append")

        info "Booting SquashFS image in QEMU (memory-loaded overlay)..."
        info "  Image   : $image"
        info "  Kernel  : $kernel"
        info "  Initrd  : $initrd"
        info "  Memory  : ${memory}MB, CPUs: $cpus"
        info "  SSH     : ssh -p $ssh_port root@localhost"
        info "  Exit    : Ctrl-A X (serial) or close window (graphic)"

        qemu-system-x86_64 "${qemu_args[@]}"
        rm -f "$tmp_disk"
    else
        if [ -n "$kernel" ] && [ -n "$initrd" ]; then
            qemu_args+=(-drive file="$image",format="$qemu_fmt",if=virtio)
            local append="root=/dev/vda1 kloop= console=ttyS0 $extra_append"
            qemu_args+=(-kernel "$kernel" -initrd "$initrd" -append "$append")
        else
            if [ -n "$kernel" ] || [ -n "$initrd" ]; then
                warn "Both -k and -i must be specified for external kernel boot; falling back to disk boot"
            fi
            local auto_kernel="$image_dir/vmlinuz"
            local auto_initrd="$image_dir/initramfs-vhdboot.img"
            if [ -f "$auto_kernel" ] && [ -f "$auto_initrd" ]; then
                qemu_args+=(-drive file="$image",format="$qemu_fmt",if=virtio)
                local append="root=/dev/vda1 console=ttyS0 $extra_append"
                qemu_args+=(-kernel "$auto_kernel" -initrd "$auto_initrd" -append "$append")
            else
                qemu_args+=(-drive file="$image",format="$qemu_fmt",if=virtio)
                qemu_args+=(-boot order=c)
            fi
        fi

        info "Booting image in QEMU..."
        info "  Image   : $image ($qemu_fmt)"
        info "  Memory  : ${memory}MB, CPUs: $cpus"
        info "  SSH     : ssh -p $ssh_port root@localhost"
        info "  Exit    : Ctrl-A X (serial) or close window (graphic)"

        qemu-system-x86_64 "${qemu_args[@]}"
    fi
}

list_combinations() {
    echo "vd-boot v${VD_BOOT_VERSION}"
    echo ""
    echo "Distributions: $DISTROS"
    echo "Boot modes:    $BOOT_MODES"
    echo "Disk types:    $DISK_TYPES"
    echo "Formats:       $FORMATS"
    echo "initramfs:     $INITRAMFS_METHODS"
    echo ""
    echo "Default initramfs per distribution:"
    echo "  archlinux:  mkinitcpio"
    echo "  ubuntu:     mkinitramfs"
    echo "  debian:     mkinitramfs"
    echo "  deepin:     mkinitramfs"
    echo "  fedora:     dracut"
    echo "  opensuse:   dracut"
    echo ""
    echo "Format notes:"
    echo "  vhd/vmdk/vdi/qcow2/vhdx: Disk images with GPT partition table + ext4 rootfs"
    echo "  squashfs: Read-only compressed filesystem, booted with tmpfs overlay (runs in RAM)"
    echo ""
    echo "All VHD combinations:"
    for d in $DISTROS; do
        for b in $BOOT_MODES; do
            for t in $DISK_TYPES; do
                echo "  $d-$b-$t.vhd"
            done
        done
    done
}

clean_output() {
    local workdir="${WORKDIR:-/tmp/vhdboot-build}"
    info "Cleaning output directory: $OUTPUT_DIR"
    if [ -d "$OUTPUT_DIR" ]; then
        rm -f "$OUTPUT_DIR"/*.vhd "$OUTPUT_DIR"/*.vmdk "$OUTPUT_DIR"/*.vdi \
              "$OUTPUT_DIR"/*.qcow2 "$OUTPUT_DIR"/*.vhdx "$OUTPUT_DIR"/*.squashfs \
              "$OUTPUT_DIR"/*.img "$OUTPUT_DIR"/*.raw \
              "$OUTPUT_DIR"/.qemu-squashfs-carrier.raw \
              "$OUTPUT_DIR"/vmlinuz "$OUTPUT_DIR"/initramfs-vhdboot.img
        info "Output directory cleaned"
    fi
    if [ -d "$workdir" ]; then
        warn "Temp build directory exists: $workdir"
        echo "Remove it manually with: sudo rm -rf $workdir"
    fi
}

case "${1:-}" in
    build)
        [ -z "${2:-}" ] && { err "Missing distribution name. Usage: $0 build <distribution> [options]"; }
        build_one "$2" "${@:3}"
        ;;
    build-all)
        build_all "${2:-}"
        ;;
    qemu|test)
        [ -z "${2:-}" ] && { err "Missing image path. Usage: $0 qemu <image> [options]"; }
        qemu_boot "$2" "${@:3}"
        ;;
    list)
        list_combinations
        ;;
    clean)
        clean_output
        ;;
    version|-V|--version)
        echo "vd-boot v${VD_BOOT_VERSION}"
        ;;
    -h|--help)
        usage
        ;;
    "")
        usage
        ;;
    *)
        err "Unknown command: $1. Run '$0 --help' for usage."
        ;;
esac
