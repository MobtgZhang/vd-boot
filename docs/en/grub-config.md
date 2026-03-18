# GRUB Configuration Guide

This document explains how to configure GRUB to boot Linux from a virtual disk file.

## Using boot.sh (Recommended)

`boot.sh` can automatically generate and install GRUB boot configuration.

### Install Boot Entry

```bash
# Add a kloop boot entry (requires root)
sudo ./boot.sh install -v /vhd/arch.vhd -n "Arch Linux VHD"

# Add a vloop boot entry
sudo ./boot.sh install -v /vhd/ubuntu.vhd -b vloop -n "Ubuntu VHD"

# QCOW2 format
sudo ./boot.sh install -v /vhd/arch.qcow2 -n "Arch Linux QCOW2"

# VHDX format
sudo ./boot.sh install -v /vhd/arch.vhdx -n "Arch Linux VHDX"

# SquashFS format (boot mode auto-detected)
sudo ./boot.sh install -v /vhd/rootfs.squashfs -n "Arch Linux SquashFS"

# Load kernel from inside a fixed-size VHD
sudo ./boot.sh install -v /vhd/arch-fixed.vhd -I -n "Arch Linux (Fixed)"

# Install GRUB to another disk (e.g. USB drive /dev/sdb)
sudo ./boot.sh install -v /vhd/arch.vhd -g -t /dev/sdb
```

### Generate Config Only (No Install)

```bash
./boot.sh generate -v /vhd/fedora.vhd -b kloop
```

### boot.sh Options

| Option            | Description                                              |
| ----------------- | -------------------------------------------------------- |
| `-v, --vhd`      | Disk image path                                          |
| `-b, --boot`     | Boot mode: `kloop` / `vloop` / `squashfs`                |
| `-n, --name`     | GRUB menu display name                                   |
| `-p, --part`     | vloop partition number: `p1`/`p2`/`p3`...                |
| `-k, --kernel`   | Kernel path (default: vmlinuz in same dir as VHD)        |
| `-i, --initrd`   | initrd path (default: initramfs-vhdboot.img in same dir) |
| `-I, --inside`   | Load kernel from inside VHD (fixed-size VHD only)        |
| `-g, --install-grub` | Install GRUB to specified disk (use with `-t`)       |
| `-t, --target`   | GRUB install target device (e.g. `/dev/sdb`)             |

## Manual GRUB Configuration

If you prefer not to use `boot.sh`, you can write the GRUB configuration manually.

### File Placement

Place the following three files in the same directory (e.g. `/vhd/`):

```
/vhd/
├── archlinux-kloop-dynamic.vhd   # Virtual disk
├── vmlinuz                        # Kernel
└── initramfs-vhdboot.img          # initramfs
```

### kloop Mode Configuration

```
menuentry 'Arch Linux VHD (kloop)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set vhdfile="$vhddir/arch-kloop-dynamic.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} kloop=$vhdfile kroot=/dev/mapper/loop0p1
    initrd $vhddir/initramfs-vhdboot.img
}
```

### vloop Mode Configuration

```
menuentry 'Arch Linux VHD (vloop)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set vhdfile="$vhddir/arch-vloop-dynamic.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} vloop=$vhdfile vlooppart=p1
    initrd $vhddir/initramfs-vhdboot.img
}
```

### SquashFS Mode Configuration

```
menuentry 'Arch Linux SquashFS (RAM overlay)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set squashfile="$vhddir/arch.squashfs"
    search --no-floppy -f --set=root $squashfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} squashfs=$squashfile
    initrd $vhddir/initramfs-vhdboot.img
}
```

### Load Kernel from Inside VHD (Fixed-Size VHD)

```
menuentry 'Arch Linux VHD (kloop, internal)' --class arch --class gnu-linux {
    set vhdfile="/vhd/arch-kloop-fixed.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    insmod part_gpt
    insmod part_msdos
    insmod ext2
    loopback lp0 $vhdfile
    linux (lp0,1)/boot/vmlinuz root=UUID=${uuid} kloop=$vhdfile kroot=/dev/mapper/loop0p1
    initrd (lp0,1)/boot/initramfs-vhdboot.img
}
```

### LVM Partition

```
menuentry 'Arch Linux VHD (kloop+LVM)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set vhdfile="$vhddir/arch-lvm.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} kloop=$vhdfile kroot=/dev/mapper/vg0-root klvm=vg0
    initrd $vhddir/initramfs-vhdboot.img
}
```

## GRUB Menu Visibility

`boot.sh install` automatically checks and fixes the following settings to ensure the GRUB menu is visible:

- Changes `GRUB_TIMEOUT_STYLE=hidden` to `GRUB_TIMEOUT_STYLE=menu`
- Changes `GRUB_TIMEOUT=0` to `GRUB_TIMEOUT=5`

These settings are in `/etc/default/grub`.

## More GRUB Configuration Examples

The `grub/grub.cfg` file in the project contains complete GRUB configuration examples for multiple formats and modes, including VHD, VMDK, VDI, QCOW2, VHDX, SquashFS, and more.
