#!/bin/bash
# VLOOP / SquashFS - Dracut pre-mount hook

. /lib/dracut-lib.sh 2>/dev/null || true

VLOOP=$(getarg vloop=)
VLOOPPART=$(getarg vlooppart=)
VLOOPFSTYPE=$(getarg vloopfstype=)
HOSTFSTYPE=$(getarg hostfstype=)
SQUASHFS=$(getarg squashfs=)

export VLOOP VLOOPPART VLOOPFSTYPE HOSTFSTYPE SQUASHFS

# SquashFS boot: mount squashfs as read-only lower, tmpfs as upper, overlay as root
if [ -n "$SQUASHFS" ]; then
    HOSTDEV="${root#block:}"
    ismounted "$NEWROOT" && umount "$NEWROOT"

    mkdir -p /host
    [ -z "${HOSTFSTYPE}" ] && HOSTFSTYPE="$(blkid -s TYPE -o value "$HOSTDEV" 2>/dev/null)"
    [ -z "${HOSTFSTYPE}" -o "${HOSTFSTYPE}" = "ntfs" ] && HOSTFSTYPE="ntfs-3g"
    [ "${HOSTFSTYPE}" = "ntfs-3g" ] || modprobe ${HOSTFSTYPE} 2>/dev/null
    mount -t "${HOSTFSTYPE}" -o ro $HOSTDEV /host

    modprobe squashfs 2>/dev/null
    modprobe overlay 2>/dev/null

    mkdir -p /run/vdboot/squashfs /run/vdboot/tmpfs /run/vdboot/work

    mount -t squashfs -o ro "/host${SQUASHFS}" /run/vdboot/squashfs
    mount -t tmpfs -o size=50% tmpfs /run/vdboot/tmpfs
    mkdir -p /run/vdboot/tmpfs/upper /run/vdboot/tmpfs/work

    mount -t overlay overlay \
        -o lowerdir=/run/vdboot/squashfs,upperdir=/run/vdboot/tmpfs/upper,workdir=/run/vdboot/tmpfs/work \
        $NEWROOT

    mkdir -p ${NEWROOT}/host
    mount -R /host ${NEWROOT}/host
    return 0 2>/dev/null || true
fi

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
