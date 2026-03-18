# Getting Started

This guide helps you quickly build your first bootable virtual disk image.

## Prerequisites

- Linux system (Ubuntu/Debian/Fedora/Arch recommended as build host)
- Root privileges
- Base dependencies: `qemu-utils`, `parted`, `e2fsprogs`, `kpartx`, `wget` or `curl`

### Install Dependencies

```bash
# Debian/Ubuntu
sudo apt install qemu-utils parted e2fsprogs kpartx wget

# Fedora
sudo dnf install qemu-img parted e2fsprogs kpartx wget

# Arch Linux
sudo pacman -S qemu-img parted e2fsprogs multipath-tools wget
```

## First Image: Build an Arch Linux VHD

```bash
# Clone the project
git clone https://github.com/mobtgzhang/vd-boot.git
cd vd-boot

# Build an Arch Linux image (defaults: kloop boot, dynamic disk, VHD format, 16GB)
sudo ./run.sh build archlinux
```

After the build completes, the image file is located at `output/archlinux-kloop-dynamic.vhd`, and `vmlinuz` and `initramfs-vhdboot.img` are automatically copied to the `output/` directory.

## Test with QEMU

```bash
# Launch with built-in QEMU support (serial console)
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd

# Graphical mode with 4GB memory
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -m 4096 -g

# SSH access (default port 2222, password: vdboot)
ssh -p 2222 root@localhost
```

## Boot on Real Hardware

Copy the image and boot files to the target disk, then configure GRUB:

```bash
# Place the image on a host partition (e.g. /vhd/)
sudo mkdir -p /vhd
sudo cp output/archlinux-kloop-dynamic.vhd /vhd/
sudo cp output/vmlinuz /vhd/
sudo cp output/initramfs-vhdboot.img /vhd/

# Use boot.sh to automatically add a GRUB boot entry
sudo ./boot.sh install -v /vhd/archlinux-kloop-dynamic.vhd -n "Arch Linux VHD"
```

After rebooting, select the entry from the GRUB menu to boot into the Linux system inside the VHD.

## More Examples

```bash
# Build Ubuntu, vloop mode, VMDK format
sudo ./run.sh build ubuntu -b vloop -f vmdk

# Build Fedora, fixed-size disk, 32GB
sudo ./run.sh build fedora -d fixed -s 32

# Build Debian, SquashFS format (read-only compressed, runs in RAM)
sudo ./run.sh build debian -f squashfs

# Build all distro/mode/disk combinations
sudo ./run.sh build-all
```

## Next Steps

- [Build Guide](build-guide.md) — Full build options reference
- [Boot Modes](boot-modes.md) — How kloop, vloop, and SquashFS work
- [GRUB Configuration](grub-config.md) — Detailed boot configuration
- [Distro Notes](distros.md) — Distro-specific requirements and notes
