# Project Architecture

## Directory Structure

```
vd-boot/
├── run.sh                          # Main entry script (build/qemu/list/clean)
├── boot.sh                         # GRUB boot entry installation script
├── README.md                       # Project overview (English)
├── README_CN.md                    # Project overview (Chinese)
├── LICENSE                         # GPLv3 license
├── config/
│   ├── mirrors.conf                # Mirror URLs and version configuration
│   ├── initramfs-defaults.conf     # Default initramfs tool per distro
│   ├── dracut-vhdboot.conf         # dracut build configuration
│   ├── mkinitcpio-kloop.conf       # mkinitcpio kloop mode configuration
│   └── mkinitcpio-vloop.conf       # mkinitcpio vloop mode configuration
├── lib/
│   ├── common.sh                   # Common functions (logging, validation, versions)
│   ├── disk.sh                     # Disk creation, partitioning, format conversion
│   └── chroot.sh                   # chroot management, initramfs building
├── boot/
│   ├── vhdmount-kloop.sh           # kloop/squashfs dracut hook script
│   ├── vhdmount-vloop.sh           # vloop/squashfs dracut hook script
│   ├── vhdmount-initramfs-tools.sh # initramfs-tools hook script
│   ├── mkinitcpio-install-vhdboot  # mkinitcpio install hook
│   └── mkinitcpio-hooks-vhdboot    # mkinitcpio runtime hook
├── grub/
│   └── grub.cfg                    # GRUB configuration examples (multi-format, multi-mode)
├── distros/
│   ├── archlinux/build.sh          # Arch Linux build script
│   ├── ubuntu/build.sh             # Ubuntu build script
│   ├── debian/build.sh             # Debian build script
│   ├── deepin/build.sh             # Deepin build script
│   ├── fedora/build.sh             # Fedora build script
│   └── opensuse/build.sh           # OpenSUSE build script
├── docs/
│   ├── en/                         # English documentation
│   └── CN/                         # Chinese documentation
└── output/                         # Default build output directory
```

## Build Process

The complete build workflow:

```
run.sh build <distro> [options]
  │
  ├─ 1. Parse and validate arguments
  │     Verify distro, boot mode, disk type, format, etc.
  │
  ├─ 2. Invoke distros/<distro>/build.sh
  │     │
  │     ├─ 2a. Create disk image (lib/disk.sh → create_disk)
  │     │      Use qemu-img to create a virtual disk of the specified format and type
  │     │
  │     ├─ 2b. Partition and format (lib/disk.sh → partition_and_mount)
  │     │      GPT partition table + ext4 filesystem
  │     │      Mount as loop device via losetup
  │     │
  │     ├─ 2c. Install base system
  │     │      Arch: Extract bootstrap tarball
  │     │      Ubuntu/Debian/Deepin: debootstrap
  │     │      Fedora: dnf --installroot
  │     │      OpenSUSE: zypper --root
  │     │
  │     ├─ 2d. chroot configuration (lib/chroot.sh)
  │     │      Install kernel, configure networking, set password
  │     │      Install vhdboot hook scripts
  │     │      Build initramfs (dracut/mkinitcpio/mkinitramfs)
  │     │
  │     ├─ 2e. Copy boot files
  │     │      vmlinuz + initramfs-vhdboot.img → output directory
  │     │
  │     └─ 2f. Unmount and cleanup
  │            umount, losetup -d
  │
  └─ 3. Build complete
        Output file: output/<distro>-<boot>-<disk>.<fmt>
```

## Boot Process

```
Select VHD boot entry from GRUB menu
  │
  ├─ GRUB loads vmlinuz and initramfs-vhdboot.img
  │
  ├─ Linux kernel starts, decompresses initramfs
  │
  ├─ vhdboot hook script in initramfs executes
  │   ├─ dracut: /lib/dracut/hooks/pre-mount/10-vhdmount.sh
  │   ├─ mkinitcpio: /hooks/vhdboot
  │   └─ initramfs-tools: /scripts/init-premount/vhdboot
  │
  ├─ Hook script processing:
  │   ├─ Parse kernel parameters (kloop/vloop/squashfs)
  │   ├─ Mount host partition to /host via UUID
  │   ├─ Mount virtual disk (loop + kpartx/mapper)
  │   │   or mount SquashFS + tmpfs overlay
  │   └─ Mount root filesystem to $NEWROOT
  │
  └─ System boots normally (init → systemd)
```

## Module Reference

### run.sh

Main project entry point with these subcommands:

- `build` — Build a single image
- `build-all` — Batch-build all combinations
- `qemu` — QEMU boot test
- `list` — List supported combinations
- `clean` — Clean output directory
- `version` — Show version

### boot.sh

GRUB boot entry management script:

- `install` — Generate and install GRUB config to `/etc/grub.d/45_vhdboot`, then run `update-grub`
- `generate` — Only output GRUB config snippet to stdout

### lib/common.sh

Common utility functions:

- Logging (info/warn/err/debug)
- Dependency checking
- Cleanup trap management
- fstab generation
- Root password and network configuration

### lib/disk.sh

Disk operations:

- `create_disk` — Create virtual disk using qemu-img
- `partition_and_mount` — Partition (GPT + ext4) and mount
- `unmount_disk` — Safe unmount
- `convert_format` — Format conversion
- `create_squashfs` — Create SquashFS image

### lib/chroot.sh

chroot environment management:

- `prepare_chroot` / `cleanup_chroot` — Mount/unmount proc/sys/dev etc.
- `run_chroot` — Execute commands inside chroot
- `install_vhdboot` — Install vhdboot hooks into initramfs
- `build_initramfs` — Build initramfs with vhdboot hooks
- `copy_boot_files_to_output` — Copy kernel and initramfs to output directory

### boot/ Directory

Boot hook scripts that get installed into the virtual disk's initramfs:

- `vhdmount-kloop.sh` — dracut pre-mount hook for kloop and squashfs modes
- `vhdmount-vloop.sh` — dracut pre-mount hook for vloop and squashfs modes
- `vhdmount-initramfs-tools.sh` — initramfs-tools hook (Ubuntu/Debian/Deepin)
- `mkinitcpio-install-vhdboot` — mkinitcpio install hook (Arch Linux)
- `mkinitcpio-hooks-vhdboot` — mkinitcpio runtime hook (Arch Linux)
