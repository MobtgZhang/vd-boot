#!/bin/bash
# KLOOP / SquashFS - Dracut pre-mount hook

. /lib/dracut-lib.sh 2>/dev/null || true

KLOOP=$(getarg kloop=)
KROOT=$(getarg kroot=)
KLOOPFSTYPE=$(getarg kloopfstype=)
KLVM=$(getarg klvm=)
HOSTFSTYPE=$(getarg hostfstype=)
HOSTHIDDEN=$(getarg hosthidden=)
SQUASHFS=$(getarg squashfs=)

export KLOOP KROOT KLOOPFSTYPE KLVM HOSTFSTYPE HOSTHIDDEN SQUASHFS

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
