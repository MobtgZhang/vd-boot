# vd-boot

[中文文档](README_cn.md)

Download and build bootable VHD/VMDK/VDI/QCOW2/VHDX/SquashFS virtual disk files from Tsinghua University mirrors, supporting direct Linux boot from virtual disks via kloop or vloop mode.

## Features

- **Distros**: Arch Linux, Ubuntu, Fedora, Debian, Deepin, OpenSUSE
- **Boot Modes**: kloop, vloop, SquashFS (RAM overlay)
- **Disk Types**: fixed, dynamic
- **Output Formats**: VHD, VMDK, VDI, QCOW2, VHDX, SquashFS
- **Mirror Source**: Tsinghua University mirrors (mirrors.tuna.tsinghua.edu.cn)
- **QEMU Testing**: Built-in QEMU boot with serial and graphical modes
- **GRUB Config**: Automatic GRUB boot entry generation and installation

## Quick Start

```bash
# Install dependencies (Debian/Ubuntu)
sudo apt install qemu-utils parted e2fsprogs kpartx wget

# Build an Arch Linux virtual disk
sudo ./run.sh build archlinux

# Test with QEMU
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd

# Add GRUB boot entry to host machine
sudo ./boot.sh install -v /vhd/archlinux-kloop-dynamic.vhd -n "Arch Linux VHD"
```

## Common Commands

```bash
sudo ./run.sh build <distro> [options]    # Build a single image
sudo ./run.sh build-all                   # Build all combinations
sudo ./run.sh qemu <image> [options]      # QEMU boot test
./run.sh list                             # List supported combinations
./run.sh clean                            # Clean output directory
```

## Directory Structure

```
vd-boot/
├── run.sh              # Main entry script
├── boot.sh             # GRUB boot entry installation script
├── config/             # Mirror, version, and initramfs configuration
├── lib/                # Common function libraries (disk, chroot, utils)
├── boot/               # initramfs boot hook scripts
├── grub/               # GRUB configuration examples
├── distros/            # Per-distro build scripts
├── docs/               # Documentation (en / CN)
└── output/             # Default output directory
```

## Documentation

| Document | Description |
| -------- | ----------- |
| [Getting Started](docs/en/getting-started.md) | Install deps, build first image, boot test |
| [Build Guide](docs/en/build-guide.md) | Full build options, batch builds, version config |
| [Boot Modes](docs/en/boot-modes.md) | How kloop, vloop, and SquashFS work |
| [GRUB Configuration](docs/en/grub-config.md) | boot.sh usage and manual GRUB setup |
| [Disk Formats](docs/en/disk-formats.md) | VHD/VMDK/VDI/QCOW2/VHDX/SquashFS comparison |
| [Distro Notes](docs/en/distros.md) | Distro-specific requirements and notes |
| [QEMU Testing](docs/en/qemu-testing.md) | QEMU boot options and troubleshooting |
| [Architecture](docs/en/architecture.md) | Directory structure, build flow, module reference |

## License

GNU General Public License v3.0
