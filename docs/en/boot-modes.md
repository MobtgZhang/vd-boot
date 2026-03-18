# Boot Modes

vd-boot supports three boot modes, each using a different method to boot Linux from a virtual disk file.

## Mode Overview

| Mode     | Mechanism                    | Read/Write    | Supported Formats              | Description                          |
| -------- | ---------------------------- | ------------- | ------------------------------ | ------------------------------------ |
| kloop    | loop + kpartx partition map  | Read-Write    | VHD, VMDK, VDI, QCOW2, VHDX   | Best compatibility, recommended default |
| vloop    | loop + device-mapper         | Read-Write    | VHD, VMDK, VDI, QCOW2, VHDX   | Similar to kloop, different partition mapping |
| squashfs | squashfs + tmpfs overlay     | Read-only + overlay | SquashFS                 | Runs in RAM, changes lost on reboot  |

## kloop Mode

kloop mode uses `losetup` to mount the virtual disk file as a loop device, then uses `kpartx` to create partition mapping devices (e.g. `/dev/mapper/loop0p1`), and finally mounts it as the root filesystem.

### Boot Flow

```
GRUB loads kernel and initramfs
  ↓
vhdmount-kloop.sh in initramfs is executed
  ↓
Mount host partition to /host (found by UUID)
  ↓
losetup mounts /host/<vhd-path> as loop device
  ↓
kpartx creates partition mapping /dev/mapper/loop0p1
  ↓
mount /dev/mapper/loop0p1 as root
  ↓
System boots normally
```

### Kernel Parameters

```
root=UUID=<host-partition-UUID> kloop=<vhd-path> kroot=/dev/mapper/loop0p1
```

- `kloop=` — Path to the virtual disk file on the host partition
- `kroot=` — Root partition device inside the VHD (default: first partition `loop0p1`)
- `kloopfstype=` — Optional, filesystem type inside VHD (default: auto-detect, usually ext4)
- `hostfstype=` — Optional, host partition filesystem type (default: auto-detect)
- `klvm=` — Optional, LVM volume group name if VHD uses LVM

### LVM Support

kloop supports VHDs containing LVM:

```
root=UUID=<uuid> kloop=/vhd/arch-lvm.vhd kroot=/dev/mapper/vg0-root klvm=vg0
```

## vloop Mode

vloop mode is similar to kloop but uses a different partition mapping method. vloop accesses VHD partitions directly through loop device partition mappings (`/dev/mapper/loop0pN`).

### Kernel Parameters

```
root=UUID=<host-partition-UUID> vloop=<vhd-path> vlooppart=p1
```

- `vloop=` — Path to the virtual disk file
- `vlooppart=` — Partition number: `p1`=first partition, `p2`=second partition, etc.
- `vloopfstype=` — Optional, filesystem type inside VHD
- `hostfstype=` — Optional, host partition filesystem type

## SquashFS Mode

SquashFS mode compresses the entire root filesystem into a read-only SquashFS image. At boot time, it is mounted into memory with a tmpfs overlay providing a writable layer. This is similar to how a Live CD works — all changes are lost on reboot.

### Boot Flow

```
GRUB loads kernel and initramfs
  ↓
Hook script in initramfs is executed
  ↓
Mount host partition to /host (read-only)
  ↓
mount -t squashfs /host/<squashfs-path> /run/vdboot/squashfs (read-only)
  ↓
mount -t tmpfs /run/vdboot/tmpfs (writable, 50% of RAM)
  ↓
mount -t overlay (lower=squashfs, upper=tmpfs) as root
  ↓
System runs entirely in RAM
```

### Kernel Parameters

```
root=UUID=<host-partition-UUID> squashfs=<squashfs-path>
```

### Characteristics

- Very small image file (xz compressed)
- System runs entirely in RAM — fast performance
- All changes lost on reboot (no persistence)
- Always requires external kernel and initramfs (cannot load from inside SquashFS)
- Sufficient memory recommended (at least 2GB, 4GB+ preferred)

## Kernel Loading Methods

Booting from a virtual disk requires GRUB to load the kernel (vmlinuz) and initramfs. There are two loading methods:

| Method                        | Applies To             | Description                                          |
| ----------------------------- | ---------------------- | ---------------------------------------------------- |
| **External loading** (default) | All formats and types  | vmlinuz and initramfs-vhdboot.img alongside the VHD  |
| **Internal loading** (`--inside`) | Fixed-size VHD only | Load from /boot inside VHD, no extra files needed    |

Dynamic VHD/VMDK/VDI/QCOW2/VHDX cannot be parsed by GRUB's loopback, so external kernel loading is required. The build process automatically copies `vmlinuz` and `initramfs-vhdboot.img` to the output directory.

## initramfs Tools

vd-boot injects boot hook scripts when building the initramfs. Three initramfs build tools are supported:

| Tool        | Default For              | Hook Install Location                                     |
| ----------- | ------------------------ | --------------------------------------------------------- |
| dracut      | Fedora, OpenSUSE        | `/lib/dracut/hooks/pre-mount/` and dracut module          |
| mkinitcpio  | Arch Linux              | `/usr/lib/initcpio/install/vhdboot` and `hooks/vhdboot`   |
| mkinitramfs | Ubuntu, Debian, Deepin  | `/usr/share/initramfs-tools/scripts/init-premount/vhdboot` |

You can override the default tool with the `-m` flag, but using the distro's default tool is generally recommended.
