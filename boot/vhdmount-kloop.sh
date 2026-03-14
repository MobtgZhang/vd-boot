#!/bin/bash
# KLOOP - Dracut pre-mount hook

. /lib/dracut-lib.sh 2>/dev/null || true

KLOOP=$(getarg kloop=)
KROOT=$(getarg kroot=)
KLOOPFSTYPE=$(getarg kloopfstype=)
KLVM=$(getarg klvm=)
HOSTFSTYPE=$(getarg hostfstype=)
HOSTHIDDEN=$(getarg hosthidden=)

export KLOOP KROOT KLOOPFSTYPE KLVM HOSTFSTYPE HOSTHIDDEN

if [ -n "$KLOOP" ]; then
    HOSTDEV="${root#block:}"
    [ -n "$KROOT" ] || root="/dev/loop0"
    [ -n "$KROOT" ] && root="$KROOT"
    realroot="$root"
    export root
    ismounted "$NEWROOT" && umount "$NEWROOT"

    mkdir -p /host
    [ -z "${HOSTFSTYPE}" ] && HOSTFSTYPE="$(blkid -s TYPE -o value "$HOSTDEV")"
    [ -z "${HOSTFSTYPE}" -o "${HOSTFSTYPE}" = "ntfs" ] && HOSTFSTYPE="ntfs-3g"
    [ "${HOSTFSTYPE}" = "ntfs-3g" ] || modprobe ${HOSTFSTYPE}
    mount -t "${HOSTFSTYPE}" -o rw $HOSTDEV /host

    if [ "${KLOOP#/}" != "${KLOOP}" ]; then
        modprobe loop
        kpartx -av /host$KLOOP
        [ -e "$realroot" ] || sleep 3
    fi

    if [ -n "$KLVM" ]; then
        modprobe dm-mod
        vgscan
        vgchange -ay "$KLVM"
        [ -e "$realroot" ] || sleep 3
    fi

    [ -z "${KLOOPFSTYPE}" ] && KLOOPFSTYPE="$(blkid -s TYPE -o value "$realroot")"
    [ -z "${KLOOPFSTYPE}" ] && KLOOPFSTYPE="ext4"
    [ -e "$realroot" ] || sleep 3
    mount -t "${KLOOPFSTYPE}" -o rw $realroot $NEWROOT

    [ "${HOSTHIDDEN}" != "y" ] && { [ -d "${NEWROOT}/host" ] || mkdir -p ${NEWROOT}/host; mount -R /host ${NEWROOT}/host; }
fi
