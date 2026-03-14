#!/bin/bash
# Common function library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REBUILD2_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${REBUILD2_ROOT}/config/mirrors.conf"

[ -f "$CONFIG" ] && source "$CONFIG"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

check_root() {
    [ "$(id -u)" -eq 0 ] || err "Please run this script as root or with sudo"
}

check_deps() {
    command -v qemu-img >/dev/null 2>&1 || err "Please install qemu-utils: apt install qemu-utils / pacman -S qemu"
    command -v parted >/dev/null 2>&1 || err "Please install parted"
    command -v mkfs.ext4 >/dev/null 2>&1 || err "Please install e2fsprogs"
}

cleanup_mount() {
    local mnt="$1"
    [ -n "$mnt" ] && [ -d "$mnt" ] && mountpoint -q "$mnt" && umount -R "$mnt" 2>/dev/null || true
}
