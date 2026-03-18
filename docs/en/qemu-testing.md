# QEMU Testing Guide

vd-boot includes built-in QEMU boot support for quickly testing built virtual disk images.

## Prerequisites

```bash
# Debian/Ubuntu
sudo apt install qemu-system-x86

# Fedora
sudo dnf install qemu-system-x86

# Arch Linux
sudo pacman -S qemu-system-x86
```

UEFI boot also requires OVMF firmware:

```bash
# Debian/Ubuntu
sudo apt install ovmf

# Fedora
sudo dnf install edk2-ovmf

# Arch Linux
sudo pacman -S edk2-ovmf
```

## Basic Usage

```bash
sudo ./run.sh qemu <image-file> [options]
```

## Options

| Option          | Description                    | Default    |
| --------------- | ------------------------------ | ---------- |
| `-m, --memory`  | Memory size (MB)               | 2048       |
| `-c, --cpus`    | Number of CPUs                 | 2          |
| `-k, --kernel`  | External kernel path           | auto-detect |
| `-i, --initrd`  | External initrd path           | auto-detect |
| `-a, --append`  | Extra kernel boot parameters   | —          |
| `-e, --efi`     | Use UEFI boot (requires OVMF) | off        |
| `-g, --graphic` | Graphical display              | off (serial) |
| `-p, --port`    | SSH forwarding port            | 2222       |

## Examples

### Basic Test (Serial Console)

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd
```

Exit with: `Ctrl-A X`

### Graphical Mode + More Resources

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -m 4096 -c 4 -g
```

### UEFI Boot

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -e
```

### SSH Access

QEMU forwards port 22 of the VM to port 2222 on the host by default:

```bash
# After booting, connect from another terminal
ssh -p 2222 root@localhost
# Password: vdboot
```

Custom SSH port:

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -p 3333
ssh -p 3333 root@localhost
```

### Specify External Kernel

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd \
  -k output/vmlinuz \
  -i output/initramfs-vhdboot.img
```

### Test Different Formats

```bash
# QCOW2
sudo ./run.sh qemu output/archlinux-kloop-dynamic.qcow2

# VMDK
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vmdk

# SquashFS (requires external kernel)
sudo ./run.sh qemu output/arch.squashfs \
  -k output/vmlinuz \
  -i output/initramfs-vhdboot.img
```

## Format to QEMU Mapping

| File Extension  | QEMU Format    |
| --------------- | -------------- |
| `.vhd`          | vpc            |
| `.vmdk`         | vmdk           |
| `.vdi`          | vdi            |
| `.qcow2`        | qcow2          |
| `.vhdx`         | vhdx           |
| `.squashfs`     | special        |
| `.img`/`.raw`   | raw            |

SquashFS files cannot be used directly as QEMU disks. vd-boot automatically creates a temporary ext4 carrier disk, places the SquashFS file inside it, and then boots.

## Automatic Kernel Detection

If `-k` and `-i` are not specified, the QEMU command automatically looks for `vmlinuz` and `initramfs-vhdboot.img` in the same directory as the image file. If found, it uses external kernel booting; otherwise it attempts to boot directly from the disk.

## Troubleshooting

- **Boot hangs**: Try increasing memory with `-m 4096`, especially for SquashFS mode
- **Black screen / no output**: In serial mode, check that `console=ttyS0` kernel parameter is set
- **Cannot SSH**: Verify port forwarding is correct and sshd is running inside the VM
- **UEFI boot fails**: Confirm the OVMF firmware package is installed
