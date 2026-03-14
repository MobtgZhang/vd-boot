#!/bin/bash
# VLOOP - Dracut pre-mount hook

. /lib/dracut-lib.sh 2>/dev/null || true

VLOOP=$(getarg vloop=)
VLOOPPART=$(getarg vlooppart=)
VLOOPFSTYPE=$(getarg vloopfstype=)
HOSTFSTYPE=$(getarg hostfstype=)

export VLOOP VLOOPPART VLOOPFSTYPE HOSTFSTYPE

if [ -n "$VLOOP" ]; then
    HOSTDEV="${root#block:}"
    [ -n "$VLOOPPART" ] || root=/dev/loop0
    [ -n "$VLOOPPART" ] && root=/dev/mapper/loop0${VLOOPPART}
    export root
    realroot="$root"
    ismounted "$NEWROOT" && umount "$NEWROOT"

    mkdir -p /host
    [ -z "${HOSTFSTYPE}" ] && HOSTFSTYPE="$(blkid -s TYPE -o value "$HOSTDEV")"
    [ -z "${HOSTFSTYPE}" -o "${HOSTFSTYPE}" = "ntfs" ] && HOSTFSTYPE="ntfs-3g"
    mount -t "${HOSTFSTYPE}" -o rw "${HOSTDEV}" /host

    if [ "${VLOOP#/}" != "${VLOOP}" ]; then
        modprobe loop
        kpartx -av "/host$VLOOP"
        [ -e "$realroot" ] || sleep 3
    fi

    [ -e "$realroot" ] || sleep 3
    [ -z "${VLOOPFSTYPE}" ] && VLOOPFSTYPE="$(blkid -s TYPE -o value "$realroot")"
    [ -z "${VLOOPFSTYPE}" ] && VLOOPFSTYPE="ext4"
    mount -t "${VLOOPFSTYPE}" -o rw $realroot $NEWROOT

    [ -d $NEWROOT/host ] || mkdir -p $NEWROOT/host
    mount -R /host $NEWROOT/host
fi
