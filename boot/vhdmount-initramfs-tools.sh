#!/bin/sh
# vd-boot for initramfs-tools (mkinitramfs) - runs at init-premount stage
# Parse kloop=, vloop=, or squashfs= params, mount disk image and set ROOT

PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac

for x in $(cat /proc/cmdline); do
    case $x in
        kloop=*) KLOOP="${x#kloop=}" ;;
        kroot=*) KROOT="${x#kroot=}" ;;
        vloop=*) VLOOP="${x#vloop=}" ;;
        vlooppart=*) VLOOPPART="${x#vlooppart=}" ;;
        hostfstype=*) HOSTFSTYPE="${x#hostfstype=}" ;;
        squashfs=*) SQUASHFS="${x#squashfs=}" ;;
    esac
done

# Helper: resolve host device from ROOT
resolve_hostdev() {
    case "$ROOT" in
        UUID=*) HOSTDEV="$(blkid -U "${ROOT#UUID=}" 2>/dev/null)" ; [ -z "$HOSTDEV" ] && HOSTDEV="${ROOT}" ;;
        *) HOSTDEV="${ROOT}" ;;
    esac
}

# Helper: mount host partition
mount_host() {
    local mode="${1:-rw}"
    mkdir -p /host
    [ -z "$HOSTFSTYPE" ] && HOSTFSTYPE="$(blkid -s TYPE -o value "$HOSTDEV" 2>/dev/null)"
    [ -z "$HOSTFSTYPE" ] || [ "$HOSTFSTYPE" = "ntfs" ] && HOSTFSTYPE="ntfs-3g"
    [ "$HOSTFSTYPE" = "ntfs-3g" ] || modprobe "$HOSTFSTYPE" 2>/dev/null
    mount -t "$HOSTFSTYPE" -o "$mode" "$HOSTDEV" /host
}

# SquashFS boot: mount squashfs read-only, overlay with tmpfs for writes
if [ -n "$SQUASHFS" ]; then
    resolve_hostdev
    mount_host ro

    modprobe squashfs 2>/dev/null
    modprobe overlay 2>/dev/null

    mkdir -p /run/vdboot/squashfs /run/vdboot/tmpfs

    mount -t squashfs -o ro "/host${SQUASHFS}" /run/vdboot/squashfs
    mount -t tmpfs -o size=50% tmpfs /run/vdboot/tmpfs
    mkdir -p /run/vdboot/tmpfs/upper /run/vdboot/tmpfs/work

    ROOT="overlay"
    rootmnt="${rootmnt:-/root}"
    mount -t overlay overlay \
        -o lowerdir=/run/vdboot/squashfs,upperdir=/run/vdboot/tmpfs/upper,workdir=/run/vdboot/tmpfs/work \
        "$rootmnt" 2>/dev/null || true

    mkdir -p "$rootmnt/host"
    mount -R /host "$rootmnt/host" 2>/dev/null || true

    export ROOT
    return 0 2>/dev/null || exit 0
fi

if [ -n "$KLOOP" ]; then
    resolve_hostdev
    [ -n "$KROOT" ] && ROOT="$KROOT" || ROOT="/dev/loop0"
    mount_host rw
    if [ "${KLOOP#/}" != "${KLOOP}" ]; then
        modprobe loop
        kpartx -av "/host$KLOOP"
        [ -e "$ROOT" ] || sleep 3
    fi
    export ROOT
    return 0 2>/dev/null || exit 0
fi

if [ -n "$VLOOP" ]; then
    resolve_hostdev
    [ -n "$VLOOPPART" ] && ROOT="/dev/mapper/loop0${VLOOPPART}" || ROOT="/dev/loop0"
    mount_host rw
    if [ "${VLOOP#/}" != "${VLOOP}" ]; then
        modprobe loop
        kpartx -av "/host$VLOOP"
        [ -e "$ROOT" ] || sleep 3
    fi
    export ROOT
    return 0 2>/dev/null || exit 0
fi
