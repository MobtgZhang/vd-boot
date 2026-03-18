# Build Guide

## Basic Usage

```bash
sudo ./run.sh build <distro> [options]
```

## Supported Distros

| Distro    | Build Dependencies                          | Default initramfs |
| --------- | ------------------------------------------- | ----------------- |
| archlinux | tar, zstd                                   | mkinitcpio        |
| ubuntu    | debootstrap                                 | mkinitramfs       |
| debian    | debootstrap                                 | mkinitramfs       |
| deepin    | debootstrap                                 | mkinitramfs       |
| fedora    | dnf                                         | dracut            |
| opensuse  | zypper (requires OpenSUSE host or container) | dracut            |

## Build Options

| Option            | Description                                               | Default                               |
| ----------------- | --------------------------------------------------------- | ------------------------------------- |
| `-o, --output`    | Output file path                                          | `output/<distro>-<boot>-<disk>.<fmt>` |
| `-s, --size`      | Disk size in GB (range: 1-1024)                           | 16                                    |
| `-b, --boot`      | Boot mode: `kloop` / `vloop`                              | kloop                                 |
| `-d, --disk`      | Disk type: `fixed` / `dynamic`                            | dynamic                               |
| `-f, --format`    | Output format: `vhd` / `vmdk` / `vdi` / `qcow2` / `vhdx` / `squashfs` | vhd                    |
| `-m, --initramfs` | initramfs tool: `dracut` / `mkinitramfs` / `mkinitcpio`  | follows distro default                |

## Build Examples

### Single Image

```bash
# Arch Linux, kloop, fixed-size 32GB VHD
sudo ./run.sh build archlinux -o output/arch.vhd -s 32 -b kloop -d fixed -f vhd

# Ubuntu, vloop, dynamic VMDK
sudo ./run.sh build ubuntu -b vloop -d dynamic -f vmdk

# Fedora, dracut initramfs, dynamic VHD
sudo ./run.sh build fedora -m dracut -d dynamic

# Debian, QCOW2 format
sudo ./run.sh build debian -f qcow2 -d dynamic

# Arch Linux, SquashFS (read-only compressed image)
sudo ./run.sh build archlinux -f squashfs
```

### Batch Build

```bash
# Build all distros × kloop/vloop × fixed/dynamic VHDs
sudo ./run.sh build-all

# Build all combinations for a specific distro
sudo ./run.sh build-all archlinux
sudo ./run.sh build-all debian
```

### Other Commands

```bash
# List all supported combinations
./run.sh list

# Clean output directory
./run.sh clean

# Show version
./run.sh version
```

## Version Configuration

Edit `config/mirrors.conf` to configure distro versions:

```bash
# Ubuntu: noble(24.04), jammy(22.04), focal(20.04)
UBUNTU_CODENAME="noble"

# Debian: bookworm(12), trixie(13), bullseye(11)
DEBIAN_CODENAME="bookworm"

# Deepin: apricot(20.x), beige(23.x)
DEEPIN_CODENAME="apricot"

# Fedora: 41, 40, 39
FEDORA_RELEASE="41"

# OpenSUSE Leap: 15.6, 15.5
OPENSUSE_LEAP="15.6"
```

All distros download from Tsinghua University mirrors (mirrors.tuna.tsinghua.edu.cn) by default.

## Build Output

After a successful build, the `output/` directory will contain:

| File                             | Description                          |
| -------------------------------- | ------------------------------------ |
| `<distro>-<boot>-<disk>.<fmt>`   | Virtual disk image file              |
| `vmlinuz`                        | Kernel file (for external booting)   |
| `initramfs-vhdboot.img`          | initramfs image (with vhdboot hooks) |

## Environment Variables

| Variable     | Description        | Default              |
| ------------ | ------------------ | -------------------- |
| `OUTPUT_DIR` | Output directory   | `./output`           |
| `WORKDIR`    | Build temp dir     | `/tmp/vhdboot-build` |
| `VD_DEBUG`   | Debug output       | `0` (off)            |
