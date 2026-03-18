# Disk Formats

vd-boot supports multiple virtual disk formats to accommodate different virtualization platforms and use cases.

## Format Comparison

| Format   | Extension   | Platform Compatibility       | Disk Types        | Description                              |
| -------- | ----------- | ---------------------------- | ----------------- | ---------------------------------------- |
| VHD      | `.vhd`      | Hyper-V, VirtualBox, QEMU    | fixed / dynamic   | Classic virtual hard disk, good compat   |
| VMDK     | `.vmdk`     | VMware, VirtualBox, QEMU     | fixed / dynamic   | VMware native format                     |
| VDI      | `.vdi`      | VirtualBox, QEMU             | fixed / dynamic   | VirtualBox native format                 |
| QCOW2    | `.qcow2`    | QEMU/KVM                     | fixed / dynamic   | QEMU native, supports snapshots & compression |
| VHDX     | `.vhdx`     | Hyper-V, QEMU                | fixed / dynamic   | VHD successor, supports larger capacities |
| SquashFS | `.squashfs` | Linux native                 | —                 | Read-only compressed FS, runs in RAM     |

## Disk Types

### Fixed Size

- All disk space allocated at creation time
- Better performance (no dynamic allocation needed)
- Occupies space equal to the configured size
- GRUB loopback can parse it — supports loading kernel from inside VHD

### Dynamic Size

- Grows on demand, initially very small
- Saves host storage space
- GRUB loopback cannot parse dynamic VHD/VMDK/VDI — **must use external kernel**
- Recommended for most use cases

## Format Details

### VHD (Virtual Hard Disk)

Virtual disk format used by Microsoft Hyper-V. Good compatibility across most virtualization platforms.

```bash
# Fixed-size VHD
sudo ./run.sh build archlinux -f vhd -d fixed

# Dynamic VHD
sudo ./run.sh build archlinux -f vhd -d dynamic
```

Internally created using `qemu-img create -f vpc`.

### VMDK (Virtual Machine Disk)

VMware's virtual disk format.

```bash
sudo ./run.sh build archlinux -f vmdk -d dynamic
```

- Fixed mode uses `monolithicFlat` subformat
- Dynamic mode uses `monolithicSparse` subformat

### VDI (VirtualBox Disk Image)

Oracle VirtualBox native disk format.

```bash
sudo ./run.sh build archlinux -f vdi -d dynamic
```

### QCOW2 (QEMU Copy On Write)

QEMU/KVM native format with the richest feature set.

```bash
sudo ./run.sh build archlinux -f qcow2 -d dynamic
```

- Supports snapshots
- Supports compression
- Dynamic mode uses `preallocation=off`
- Fixed mode uses `preallocation=full`

### VHDX (Virtual Hard Disk v2)

Microsoft Hyper-V second-generation virtual disk format, successor to VHD.

```bash
sudo ./run.sh build archlinux -f vhdx -d dynamic
```

- Supports up to 64TB disks
- Better data protection mechanisms

### SquashFS

Read-only compressed filesystem natively supported by the Linux kernel.

```bash
sudo ./run.sh build archlinux -f squashfs
```

- Uses xz compression, very small image size
- Mounted into RAM at boot with tmpfs overlay for writable layer
- All changes lost on reboot (similar to Live CD)
- Always requires external kernel and initramfs
- Created using `mksquashfs` (requires `squashfs-tools`)

## Internal Disk Structure

All VHD/VMDK/VDI/QCOW2/VHDX formats share the same internal structure:

```
GPT partition table
└── Partition 1 (ext4, rootfs)
    ├── /boot/vmlinuz                 # Linux kernel
    ├── /boot/initramfs-vhdboot.img   # initramfs (with vhdboot hooks)
    ├── /etc/fstab                    # Filesystem table
    └── ...                           # Complete Linux root filesystem
```

SquashFS is a directly compressed root filesystem without a partition table.

## Format Conversion

During the build process, all operations (partitioning, system installation) are performed on a raw image, then converted to the target format using `qemu-img convert`. Manual conversion is also possible:

```bash
# RAW to VHD
qemu-img convert -f raw -O vpc -o subformat=dynamic input.img output.vhd

# RAW to QCOW2
qemu-img convert -f raw -O qcow2 -o preallocation=off input.img output.qcow2

# VHD to VMDK
qemu-img convert -f vpc -O vmdk -o subformat=monolithicSparse input.vhd output.vmdk
```
