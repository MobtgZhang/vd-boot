#!/bin/sh
# vd-boot for initramfs-tools (mkinitramfs) - runs at init-premount stage
# Parse kloop= or vloop= params, mount VHD and set ROOT

for x in $(cat /proc/cmdline); do
    case $x in
        kloop=*) KLOOP="${x#kloop=}" ;;
        kroot=*) KROOT="${x#kroot=}" ;;
        vloop=*) VLOOP="${x#vloop=}" ;;
        vlooppart=*) VLOOPPART="${x#vlooppart=}" ;;
        hostfstype=*) HOSTFSTYPE="${x#hostfstype=}" ;;
    esac
done

if [ -n "$KLOOP" ]; then
    case "$ROOT" in
        UUID=*) HOSTDEV="$(blkid -U "${ROOT#UUID=}" 2>/dev/null)" ; [ -z "$HOSTDEV" ] && HOSTDEV="${ROOT}" ;;
        *) HOSTDEV="${ROOT}" ;;
    esac
    [ -n "$KROOT" ] && ROOT="$KROOT" || ROOT="/dev/loop0"
    mkdir -p /host
    [ -z "$HOSTFSTYPE" ] && HOSTFSTYPE="$(blkid -s TYPE -o value "$HOSTDEV" 2>/dev/null)"
    [ -z "$HOSTFSTYPE" ] || [ "$HOSTFSTYPE" = "ntfs" ] && HOSTFSTYPE="ntfs-3g"
    [ "$HOSTFSTYPE" = "ntfs-3g" ] || modprobe "$HOSTFSTYPE" 2>/dev/null
    mount -t "$HOSTFSTYPE" -o rw "$HOSTDEV" /host
    if [ "${KLOOP#/}" != "${KLOOP}" ]; then
        modprobe loop
        kpartx -av "/host$KLOOP"
        [ -e "$ROOT" ] || sleep 3
    fi
    export ROOT
    return 0
fi

if [ -n "$VLOOP" ]; then
    case "$ROOT" in
        UUID=*) HOSTDEV="$(blkid -U "${ROOT#UUID=}" 2>/dev/null)" ; [ -z "$HOSTDEV" ] && HOSTDEV="${ROOT}" ;;
        *) HOSTDEV="${ROOT}" ;;
    esac
    [ -n "$VLOOPPART" ] && ROOT="/dev/mapper/loop0${VLOOPPART}" || ROOT="/dev/loop0"
    mkdir -p /host
    [ -z "$HOSTFSTYPE" ] && HOSTFSTYPE="$(blkid -s TYPE -o value "$HOSTDEV" 2>/dev/null)"
    [ -z "$HOSTFSTYPE" ] || [ "$HOSTFSTYPE" = "ntfs" ] && HOSTFSTYPE="ntfs-3g"
    [ "$HOSTFSTYPE" = "ntfs-3g" ] || modprobe "$HOSTFSTYPE" 2>/dev/null
    mount -t "$HOSTFSTYPE" -o rw "$HOSTDEV" /host
    if [ "${VLOOP#/}" != "${VLOOP}" ]; then
        modprobe loop
        kpartx -av "/host$VLOOP"
        [ -e "$ROOT" ] || sleep 3
    fi
    export ROOT
    return 0
fi
