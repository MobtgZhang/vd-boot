# vd-boot

Download and build bootable VHD/VMDK/VDI virtual disk files , supporting booting Linux directly from virtual disks via kloop or vloop.

## Features

- **Distributions**: Arch Linux, Ubuntu, Fedora, Debian, Deepin, OpenSUSE
- **Boot modes**: kloop, vloop
- **Disk types**: Fixed size, Dynamic size
- **Output formats**: VHD, VMDK, VDI
- **Mirror**: Tsinghua University Mirror (mirrors.tuna.tsinghua.edu.cn)

## Requirements

- Linux system (Ubuntu/Debian/Fedora/Arch recommended as build host)
- root privileges
- Dependencies: `qemu-utils`, `parted`, `e2fsprogs`, `wget` or `curl`

### Distribution-specific dependencies and default initramfs

| Distribution | Build dependency                       | Default initramfs |
| ------------ | --------------------------------------- | ----------------- |
| Arch         | tar, zstd                               | mkinitcpio        |
| Ubuntu       | debootstrap                             | mkinitramfs       |
| Fedora       | dnf                                     | dracut            |
| Debian       | debootstrap                             | mkinitramfs       |
| Deepin       | debootstrap                             | mkinitramfs       |
| OpenSUSE     | zypper (requires OpenSUSE host or container) | dracut         |

Override with `-m dracut|mkinitramfs|mkinitcpio` for scenarios like dynamic disks.

## Directory structure

```
vd-boot/
├── run.sh              # Main entry script
├── boot.sh             # GRUB boot entry script
├── README.md           # This documentation
├── config/
│   └── mirrors.conf    # Mirror configuration (editable version numbers)
├── lib/
│   ├── common.sh      # Common functions
│   ├── disk.sh        # Disk creation and partitioning
│   └── chroot.sh      # Chroot and vhdboot installation
├── boot/
│   ├── vhdmount-kloop.sh
│   └── vhdmount-vloop.sh
├── grub/
│   └── grub.cfg       # GRUB configuration sample
├── distros/
│   ├── archlinux/build.sh
│   ├── ubuntu/build.sh
│   ├── fedora/build.sh
│   ├── debian/build.sh
│   ├── deepin/build.sh
│   └── opensuse/build.sh
└── output/            # Default output directory
```

## Usage

### Build a single image

```bash
# Basic usage
sudo ./run.sh build <distribution> [options]

# Example: Build Arch Linux, kloop, fixed 32GB, output VHD
sudo ./run.sh build archlinux -o output/arch.vhd -s 32 -b kloop -d fixed -f vhd

# Example: Build Ubuntu, vloop, dynamic disk, using mkinitramfs (Ubuntu default)
sudo ./run.sh build ubuntu -o output/ubuntu.vhd -b vloop -d dynamic

# Example: Build Fedora, specify dracut (Fedora default)
sudo ./run.sh build fedora -m dracut -d dynamic

# Example: Build Arch Linux, using mkinitcpio (Arch default)
sudo ./run.sh build archlinux -m mkinitcpio -d dynamic

# Example: Build Debian
sudo ./run.sh build debian -o output/debian.vhd

# Example: Build Deepin
sudo ./run.sh build deepin -o output/deepin.vhd

# Example: Build OpenSUSE (requires OpenSUSE host or container)
sudo ./run.sh build opensuse -o output/opensuse.vhd
```

### Option reference

| Option           | Description                                      | Default                                   |
| ---------------- | ------------------------------------------------ | ----------------------------------------- |
| `-o, --output`   | Output file path                                 | `output/<distro>-<boot>-<disk>.<fmt>`     |
| `-s, --size`     | Disk size (GB)                                   | 16                                        |
| `-b, --boot`     | Boot mode: kloop / vloop                         | kloop                                     |
| `-d, --disk`     | Disk type: fixed / dynamic                       | dynamic                                   |
| `-f, --format`   | Output format: vhd / vmdk / vdi                  | vhd                                       |
| `-m, --initramfs` | initramfs tool: dracut / mkinitramfs / mkinitcpio | Per-distribution default |

### Build all combinations

```bash
# Build all distributions × kloop/vloop × fixed/dynamic
sudo ./run.sh build-all

# Build only specified distribution
sudo ./run.sh build-all archlinux
sudo ./run.sh build-all debian
```

### List supported combinations

```bash
./run.sh list
```

## Version configuration

Edit distribution versions in `config/mirrors.conf`:

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

## Boot parameters

After building, boot via GRUB. **Kernel loading** has two modes:

| Mode                  | Applicable to              | Description                                                                 |
| --------------------- | -------------------------- | --------------------------------------------------------------------------- |
| **External** (default) | Fixed/dynamic VHD/VMDK/VDI | vmlinuz and initramfs-vhdboot.img are copied to output dir, same as VHD     |
| **Internal** (`--inside`) | **Fixed VHD only**       | Load from VHD internal /boot, no extra files needed                          |

**Note**: VHD/VMDK/VDI formats cannot be parsed by GRUB loopback, so **external kernel is required**. Build process copies `vmlinuz` and `initramfs-vhdboot.img` to the same directory as the virtual disk file.

### kloop mode (external kernel)

```
linux /vhd/vmlinuz root=UUID=<host-partition-UUID> kloop=/vhd/xxx.vhd kroot=/dev/mapper/loop0p1
initrd /vhd/initramfs-vhdboot.img
```

### vloop mode (external kernel)

```
linux /vhd/vmlinuz root=UUID=<host-partition-UUID> vloop=/vhd/xxx.vhd vlooppart=p1
initrd /vhd/initramfs-vhdboot.img
```

### Fixed VHD: load from internal (`boot.sh -I`)

Fixed VHD can use `--inside`; kernel and initramfs stay in VHD `/boot`, no need to copy to host.

See `grub/grub.cfg` for GRUB configuration samples (kloop, vloop, LVM, multi-partition).

### Add GRUB boot entry with boot.sh

`boot.sh` quickly adds VHD boot entries to system GRUB:

```bash
# Add kloop boot entry (requires root)
sudo ./boot.sh install -v /vhd/arch.vhd -n "Arch Linux VHD"

# Add vloop boot entry
sudo ./boot.sh install -v /vhd/ubuntu.vhd -b vloop -n "Ubuntu VHD"

# Generate config fragment only (no install)
./boot.sh generate -v /vhd/fedora.vhd -b kloop
```

Options: `-v` VHD path, `-b` kloop/vloop, `-n` menu name, `-p` partition (p1/p2...), `-I` load from VHD internal (fixed VHD only)

## Deepin build notes

Deepin is based on Debian. Build uses Debian bookworm as base; if Deepin mirror is available, Deepin packages are used, otherwise Debian. Use `DEEPIN_CODENAME` (apricot/beige) in `config/mirrors.conf` to select version.

## OpenSUSE build notes

OpenSUSE uses `zypper` and must be built in an OpenSUSE environment. If host is not OpenSUSE, use Docker:

```bash
# Mount vd-boot into container and run
sudo docker run --privileged -v $(pwd):/build -w /build opensuse/leap \
  /build/vd-boot/distros/opensuse/build.sh /build/output/opensuse.vhd 16 dynamic kloop vhd
```

## Environment variables

| Variable    | Description      | Default                  |
| ----------- | ---------------- | ------------------------ |
| `OUTPUT_DIR` | Output directory | `./output`               |
| `WORKDIR`    | Build temp dir   | `/tmp/vhdboot-build`     |

## License

Same as the main project.
