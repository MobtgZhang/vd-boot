#!/bin/bash
#
# vd-boot - Build bootable VHD/VMDK/VDI from Tsinghua mirror
# Distributions: archlinux, ubuntu, fedora, debian, deepin, opensuse
# Boot modes: kloop, vloop
# Disk types: fixed, dynamic
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
MIRROR_TSINGHUA="https://mirrors.tuna.tsinghua.edu.cn"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

DISTROS="archlinux ubuntu fedora debian deepin opensuse"
BOOT_MODES="kloop vloop"
DISK_TYPES="fixed dynamic"
FORMATS="vhd vmdk vdi"
INITRAMFS_METHODS="dracut mkinitramfs mkinitcpio"

usage() {
    cat << EOF
vd-boot - Build bootable virtual disks from Tsinghua mirror

Usage: $0 <command> [arguments]

Commands:
  build <distribution> [options]  Build single image
     Distribution: archlinux | ubuntu | fedora | debian | deepin | opensuse
     Options:
       -o, --output PATH   Output path (default: output/<distro>-<boot>-<disk>.<fmt>)
       -s, --size GB      Disk size (default: 16)
       -b, --boot MODE    Boot mode: kloop | vloop (default: kloop)
       -d, --disk TYPE    Disk type: fixed | dynamic (default: dynamic)
       -f, --format FMT   Output format: vhd | vmdk | vdi (default: vhd)
       -m, --initramfs M  initramfs tool: dracut | mkinitramfs | mkinitcpio (default: per distro)
                          Ubuntu/Debian/Deepin: mkinitramfs, Fedora/OpenSUSE: dracut, Arch: mkinitcpio

  build-all [distribution]  Build all combinations (optional: single distribution)

  list                    List supported combinations

Examples:
  $0 build archlinux -o arch.vhd -b kloop -d fixed
  $0 build ubuntu -s 32 -b vloop -f vmdk -m mkinitramfs
  $0 build fedora -m dracut -d dynamic
  $0 build-all archlinux
  $0 build-all

Environment variables:
  OUTPUT_DIR  Output directory (default: ./output)
  WORKDIR     Build temp directory (default: /tmp/vhdboot-build)

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
            *) shift ;;
        esac
    done
    
    [ -z "$output" ] && output="$OUTPUT_DIR/${distro}-${boot_mode}-${disk_type}.${fmt}"
    # If output is a directory (exists or path ends with /), use default filename in that dir
    if [ -d "$output" ] || [[ "$output" == */ ]]; then
        output="${output%/}/${distro}-${boot_mode}-${disk_type}.${fmt}"
    fi
    
    local build_script="$SCRIPT_DIR/distros/$distro/build.sh"
    [ -f "$build_script" ] || err "Build script not found: $distro"
    
    info "Building $distro ($boot_mode, $disk_type, ${size}GB) -> $output"
    sudo bash "$build_script" "$output" "$size" "$disk_type" "$boot_mode" "$fmt" "$initramfs_method"
}

build_all() {
    local distro_filter="$1"
    mkdir -p "$OUTPUT_DIR"
    
    for distro in $DISTROS; do
        [ -n "$distro_filter" ] && [ "$distro" != "$distro_filter" ] && continue
        [ ! -f "$SCRIPT_DIR/distros/$distro/build.sh" ] && continue
        
        for boot in $BOOT_MODES; do
            for disk in $DISK_TYPES; do
                for fmt in vhd; do  # Default output vhd only, can change to $FORMATS
                    local out="$OUTPUT_DIR/${distro}-${boot}-${disk}.${fmt}"
                    info "=== $distro | $boot | $disk | $fmt ==="
                    build_one "$distro" -o "$out" -b "$boot" -d "$disk" -f "$fmt" || warn "Build failed: $out"
                done
            done
        done
    done
    info "All done, output directory: $OUTPUT_DIR"
}

list_combinations() {
    echo "Distributions: $DISTROS"
    echo "Boot modes: $BOOT_MODES"
    echo "Disk types: $DISK_TYPES"
    echo "initramfs: $INITRAMFS_METHODS (Ubuntu/Debian/Deepin default mkinitramfs, Fedora/OpenSUSE default dracut, Arch default mkinitcpio)"
    echo "Output formats: $FORMATS"
    echo ""
    echo "Combination examples:"
    for d in $DISTROS; do
        for b in $BOOT_MODES; do
            for t in $DISK_TYPES; do
                echo "  $d-$b-$t.vhd"
            done
        done
    done
}

case "${1:-}" in
    build) build_one "$2" "${@:3}" ;;
    build-all) build_all "${2:-}" ;;
    list) list_combinations ;;
    -h|--help|*) usage ;;
esac
