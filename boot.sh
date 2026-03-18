#!/bin/bash
#
# vd-boot - GRUB boot entry script
# Adds VHD/VMDK/VDI/QCOW2/VHDX/SquashFS boot configuration to system GRUB
#
# Usage:
#   1. Install mode: sudo ./boot.sh install [options]
#      Add boot entry to system GRUB and update config
#
#   2. Generate mode: ./boot.sh generate [options]
#      Generate GRUB config fragment only, output to stdout
#
# Options:
#   -v, --vhd PATH      Disk image path (e.g. /vhd/arch.vhd, /vhd/arch.qcow2, /vhd/rootfs.squashfs)
#   -b, --boot MODE     Boot mode: kloop | vloop | squashfs (default: kloop, auto for .squashfs files)
#   -n, --name NAME     Menu display name (default: VHD Linux)
#   -p, --part PART     vloop partition: p1|p2|p3... (vloop mode, default: p1)
#   -k, --kernel PATH   Kernel path (default: same dir as VHD, or /boot/vmlinuz with --inside)
#   -i, --initrd PATH   initrd path (default: same as above, or /boot/initramfs-vhdboot.img with --inside)
#   -I, --inside        Load kernel from inside VHD (fixed VHD only, dynamic VHD/VMDK/VDI not supported)
#   -g, --install-grub  Install GRUB to specified disk (default: off, use with -t)
#   -t, --target PATH   Target device for GRUB install (e.g. /dev/sdb)
#
# Notes:
#   Default: kernel/initrd in same directory as disk image (must be on host partition)
#   --inside: Load from inside VHD, kernel in VHD /boot (fixed VHD only, GRUB loopback does not support dynamic format)
#   SquashFS: Always uses external kernel, boots into RAM with tmpfs overlay
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default config (overridable via command line)
VHDFILE="${VHDFILE:-/vhd/arch-kloop-dynamic.vhd}"
BOOT_MODE="${BOOT_MODE:-kloop}"
MENU_NAME="${MENU_NAME:-VHD Linux}"
VLOOP_PART="${VLOOP_PART:-p1}"
# kernel/initrd auto-set after parsing args based on VHD dir or --inside
KERNEL_PATH="${KERNEL_PATH:-}"
INITRD_PATH="${INITRD_PATH:-}"
KERNEL_FROM_INSIDE="${KERNEL_FROM_INSIDE:-0}"  # 1=load from inside VHD (fixed VHD only)
# Install GRUB to other disk (default: off)
INSTALL_GRUB="${INSTALL_GRUB:-0}"  # 1=install GRUB to specified disk when enabled
GRUB_INSTALL_TARGET="${GRUB_INSTALL_TARGET:-}"  # Target device, e.g. /dev/sdb or /dev/sdb1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

usage() {
    cat << EOF
vd-boot - GRUB boot entry script

Usage: $0 <command> [options]

Commands:
  install [options]  Add boot entry to system GRUB and run update-grub
  generate [options] Generate GRUB config fragment only (output to stdout)

Options:
  -v, --vhd PATH     Disk image path (default: /vhd/arch-kloop-dynamic.vhd)
                      Supports: .vhd .vmdk .vdi .qcow2 .vhdx .squashfs
  -b, --boot MODE    Boot mode: kloop | vloop | squashfs (default: kloop, auto for .squashfs files)
  -n, --name NAME    Menu display name (default: VHD Linux)
  -p, --part PART    vloop partition: p1|p2|p3... (default: p1)
  -k, --kernel PATH  Kernel path (default: same dir as VHD, or /boot/vmlinuz with --inside)
  -i, --initrd PATH  initrd path (default: same as above, or /boot/initramfs-vhdboot.img with --inside)
  -I, --inside       Load kernel from inside VHD (fixed VHD only, dynamic VHD/VMDK/VDI not supported)
  -g, --install-grub Install GRUB to specified disk (use with -t, default: off)
  -t, --target PATH  Target device for GRUB install (e.g. /dev/sdb or /dev/sdb1, use with -g)

Notes:
  Default: kernel/initrd in same directory as disk image (must be on host partition)
  --inside: Load from inside VHD, kernel in VHD /boot
  Dynamic VHD/VMDK/VDI cannot load from inside due to GRUB loopback limit, must use external kernel
  SquashFS: Always uses external kernel, boots into RAM with tmpfs overlay

Examples:
  # Load from inside VHD (fixed VHD, kernel in VHD /boot/vmlinuz)
  sudo $0 install -v /vhd/arch-fixed.vhd -I -n "Arch Linux (Fixed)"

  # External kernel (same dir as VHD)
  sudo $0 install -v /vhd/arch.vhd -n "Arch Linux VHD"

  # QCOW2 disk image
  sudo $0 install -v /vhd/arch.qcow2 -n "Arch Linux QCOW2"

  # VHDX disk image
  sudo $0 install -v /vhd/arch.vhdx -n "Arch Linux VHDX"

  # SquashFS image (boots in RAM with overlay)
  sudo $0 install -v /vhd/rootfs.squashfs -n "Arch Linux SquashFS"

  # Generate config only
  $0 generate -v /vhd/fedora.vhd -b kloop

  # Install GRUB to another disk (e.g. /dev/sdb)
  sudo $0 install -v /vhd/arch.vhd -g -t /dev/sdb

EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -v|--vhd)    VHDFILE="$2"; shift 2 ;;
            -b|--boot)   BOOT_MODE="$2"; shift 2 ;;
            -n|--name)   MENU_NAME="$2"; shift 2 ;;
            -p|--part)   VLOOP_PART="$2"; shift 2 ;;
            -k|--kernel) KERNEL_PATH="$2"; shift 2 ;;
            -i|--initrd) INITRD_PATH="$2"; shift 2 ;;
            -I|--inside) KERNEL_FROM_INSIDE=1; shift ;;
            -g|--install-grub) INSTALL_GRUB=1; shift ;;
            -t|--target) GRUB_INSTALL_TARGET="$2"; shift 2 ;;
            -h|--help)   usage; exit 0 ;;
            *)           shift ;;
        esac
    done
}

# Auto-detect squashfs boot mode from file extension
auto_detect_boot_mode() {
    case "$VHDFILE" in
        *.squashfs)
            if [ "$BOOT_MODE" = "kloop" ] || [ "$BOOT_MODE" = "vloop" ]; then
                BOOT_MODE="squashfs"
                info "Auto-detected SquashFS boot mode from file extension"
            fi
            ;;
    esac
}

# Set default kernel/initrd path based on VHD dir or --inside (when user did not specify -k/-i)
set_default_kernel_initrd() {
    auto_detect_boot_mode

    if [ "$BOOT_MODE" = "squashfs" ]; then
        local vhd_dir
        vhd_dir="$(dirname "$VHDFILE")"
        [ -z "$KERNEL_PATH" ] && KERNEL_PATH="$vhd_dir/vmlinuz" || true
        [ -z "$INITRD_PATH" ] && INITRD_PATH="$vhd_dir/initramfs-vhdboot.img" || true
    elif [ "$KERNEL_FROM_INSIDE" = "1" ]; then
        [ -z "$KERNEL_PATH" ] && KERNEL_PATH="/boot/vmlinuz" || true
        [ -z "$INITRD_PATH" ] && INITRD_PATH="/boot/initramfs-vhdboot.img" || true
    else
        local vhd_dir
        vhd_dir="$(dirname "$VHDFILE")"
        [ -z "$KERNEL_PATH" ] && KERNEL_PATH="$vhd_dir/vmlinuz" || true
        [ -z "$INITRD_PATH" ] && INITRD_PATH="$vhd_dir/initramfs-vhdboot.img" || true
    fi
}

generate_grub_config() {
    local kroot_part="$VLOOP_PART"
    [ -z "$kroot_part" ] && kroot_part="p1" || true
    local lp_part="${kroot_part#p}"
    [ -z "$lp_part" ] && lp_part="1" || true

    cat << GRUBEOF
# vd-boot entry - generated by boot.sh
# Image: $VHDFILE | Mode: $BOOT_MODE | Kernel: $([ "$BOOT_MODE" = "squashfs" ] && echo "External (SquashFS)" || ([ "$KERNEL_FROM_INSIDE" = "1" ] && echo "Inside VHD" || echo "External"))

menuentry '$MENU_NAME' --class gnu-linux --class os {
    set vhdfile="$VHDFILE"
    search --no-floppy -f --set=root \$vhdfile
    probe -u --set=uuid \${root}

GRUBEOF

    if [ "$BOOT_MODE" = "squashfs" ]; then
        echo "    linux $KERNEL_PATH root=UUID=\${uuid} squashfs=\$vhdfile"
        echo "    initrd $INITRD_PATH"
    elif [ "$KERNEL_FROM_INSIDE" = "1" ]; then
        echo "    insmod part_gpt"
        echo "    insmod part_msdos"
        echo "    insmod ext2"
        echo "    loopback lp0 \$vhdfile"
        if [ "$BOOT_MODE" = "vloop" ]; then
            echo "    linux (lp0,$lp_part)$KERNEL_PATH root=UUID=\${uuid} vloop=\$vhdfile vlooppart=$kroot_part"
        else
            echo "    linux (lp0,$lp_part)$KERNEL_PATH root=UUID=\${uuid} kloop=\$vhdfile kroot=/dev/mapper/loop0$kroot_part"
        fi
        echo "    initrd (lp0,$lp_part)$INITRD_PATH"
    else
        if [ "$BOOT_MODE" = "vloop" ]; then
            echo "    linux $KERNEL_PATH root=UUID=\${uuid} vloop=\$vhdfile vlooppart=$kroot_part"
        else
            echo "    linux $KERNEL_PATH root=UUID=\${uuid} kloop=\$vhdfile kroot=/dev/mapper/loop0$kroot_part"
        fi
        echo "    initrd $INITRD_PATH"
    fi
    echo "}"
}

fix_grub_menu_visible() {
    local grub_default="/etc/default/grub"
    if [ ! -f "$grub_default" ]; then return 0; fi

    local changed=0
    # If GRUB_TIMEOUT_STYLE=hidden, change to menu to show boot menu
    if grep -q '^GRUB_TIMEOUT_STYLE=hidden' "$grub_default" 2>/dev/null; then
        sed -i 's/^GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' "$grub_default"
        changed=1
        info "Changed GRUB_TIMEOUT_STYLE from hidden to menu, boot menu will be shown"
    fi
    # If GRUB_TIMEOUT=0, change to 5 seconds so user can see menu
    if grep -q '^GRUB_TIMEOUT=0' "$grub_default" 2>/dev/null; then
        sed -i 's/^GRUB_TIMEOUT=0/GRUB_TIMEOUT=5/' "$grub_default"
        changed=1
        info "Changed GRUB_TIMEOUT from 0 to 5, menu will show for 5 seconds"
    fi
    [ "$changed" -eq 1 ] && info "GRUB menu is now visible, you can select VHD boot entry after reboot" || true
}

install_to_grub() {
    [ "$(id -u)" -eq 0 ] || err "install command requires root, please use sudo"

    local grub_d="/etc/grub.d"
    local vhdboot_script="$grub_d/45_vhdboot"
    local grub_cfg=""

    # Ensure GRUB menu is visible (fix menu=hidden preventing system selection)
    fix_grub_menu_visible

    # Detect grub config location
    if [ -d /boot/grub ]; then
        grub_cfg="/boot/grub/grub.cfg"
    elif [ -d /boot/efi/EFI ]; then
        # Find grub.cfg under EFI
        for f in /boot/efi/EFI/*/grub.cfg; do
            [ -f "$f" ] && { grub_cfg="$f"; break; } || true
        done
    fi

    [ -z "$grub_cfg" ] && grub_cfg="/boot/grub/grub.cfg" || true

    info "Generating GRUB script: $vhdboot_script"
    {
        echo "#!/bin/sh"
        echo "# Generated by vd-boot/boot.sh"
        echo "# Custom VHD boot entry"
        echo "exec tail -n +6 \$0"
        echo ""
        generate_grub_config
    } > "$vhdboot_script"
    chmod +x "$vhdboot_script"

    info "Updating GRUB configuration..."
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o "$grub_cfg"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o "$grub_cfg"
    else
        warn "update-grub or grub-mkconfig not found, please run manually:"
        echo "  grub-mkconfig -o $grub_cfg"
        echo "or (Fedora/RHEL):"
        echo "  grub2-mkconfig -o $grub_cfg"
        exit 1
    fi

    info "VHD boot entry added to GRUB: $MENU_NAME"
    info "VHD file: $VHDFILE"

    # If install GRUB to other disk is enabled
    if [ "$INSTALL_GRUB" = "1" ]; then
        if [ -z "$GRUB_INSTALL_TARGET" ]; then
            err "Must specify -t/--target when using -g/--install-grub (e.g. /dev/sdb)"
        fi
        if [ ! -b "$GRUB_INSTALL_TARGET" ]; then
            err "Target device does not exist or is not a block device: $GRUB_INSTALL_TARGET"
        fi
        info "Installing GRUB to: $GRUB_INSTALL_TARGET"
        if command -v grub-install >/dev/null 2>&1; then
            grub-install "$GRUB_INSTALL_TARGET" || err "grub-install failed"
        elif command -v grub2-install >/dev/null 2>&1; then
            grub2-install "$GRUB_INSTALL_TARGET" || err "grub2-install failed"
        else
            err "grub-install or grub2-install not found"
        fi
        info "GRUB installed to $GRUB_INSTALL_TARGET"
    fi
}

case "${1:-}" in
    install)
        shift
        parse_args "$@"
        set_default_kernel_initrd
        install_to_grub
        ;;
    generate)
        shift
        parse_args "$@"
        set_default_kernel_initrd
        generate_grub_config
        ;;
    -h|--help|*)
        usage
        ;;
esac
