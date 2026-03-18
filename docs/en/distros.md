# Distro Notes

## Arch Linux

- **Build Dependencies**: `tar`, `zstd`
- **Default initramfs**: mkinitcpio
- **Package Source**: Tsinghua University Arch Linux mirror
- **Build Method**: Download bootstrap tarball and extract to virtual disk

```bash
sudo ./run.sh build archlinux
```

Arch Linux uses a rolling release model; the build always fetches the latest version.

## Ubuntu

- **Build Dependencies**: `debootstrap`
- **Default initramfs**: mkinitramfs (initramfs-tools)
- **Package Source**: Tsinghua University Ubuntu mirror
- **Build Method**: Install via debootstrap from mirror

```bash
sudo ./run.sh build ubuntu
```

Configure version in `config/mirrors.conf`:

```bash
# noble(24.04), jammy(22.04), focal(20.04)
UBUNTU_CODENAME="noble"
```

## Debian

- **Build Dependencies**: `debootstrap`
- **Default initramfs**: mkinitramfs (initramfs-tools)
- **Package Source**: Tsinghua University Debian mirror
- **Build Method**: Install via debootstrap from mirror

```bash
sudo ./run.sh build debian
```

Configure version in `config/mirrors.conf`:

```bash
# bookworm(12), trixie(13), bullseye(11)
DEBIAN_CODENAME="bookworm"
```

## Fedora

- **Build Dependencies**: `dnf`
- **Default initramfs**: dracut
- **Package Source**: Tsinghua University Fedora mirror
- **Build Method**: Install via dnf from mirror

```bash
sudo ./run.sh build fedora
```

Configure version in `config/mirrors.conf`:

```bash
# 41, 40, 39
FEDORA_RELEASE="41"
```

## Deepin

- **Build Dependencies**: `debootstrap`
- **Default initramfs**: mkinitramfs (initramfs-tools)
- **Package Source**: Tsinghua University Deepin mirror
- **Base System**: Based on Debian, uses Debian bookworm as base

```bash
sudo ./run.sh build deepin
```

The build uses Debian bookworm as the base system; if the Deepin mirror is available, Deepin packages are used, otherwise it falls back to Debian.

Configure version in `config/mirrors.conf`:

```bash
# apricot(20.x), beige(23.x)
DEEPIN_CODENAME="apricot"
```

## OpenSUSE

- **Build Dependencies**: `zypper`
- **Default initramfs**: dracut
- **Package Source**: Tsinghua University OpenSUSE mirror
- **Special Requirement**: **Must be built on an OpenSUSE host** (zypper is only available on OpenSUSE)

```bash
sudo ./run.sh build opensuse
```

If the host is not OpenSUSE, use a Docker container:

```bash
sudo docker run --privileged -v $(pwd):/build -w /build opensuse/leap \
  /build/run.sh build opensuse -o /build/output/opensuse.vhd
```

Configure version in `config/mirrors.conf`:

```bash
# 15.6, 15.5
OPENSUSE_LEAP="15.6"
```

## Cross-Distro initramfs Tools

Each distro has a default initramfs tool, but you can override it with the `-m` flag:

```bash
# Use dracut instead of mkinitcpio for Arch Linux
sudo ./run.sh build archlinux -m dracut

# Use dracut instead of mkinitramfs for Ubuntu
sudo ./run.sh build ubuntu -m dracut
```

Note: Cross-distro initramfs tool usage requires the target tool to be installed in the target system.

## Common Configuration

All distros after build:

- Default root password: `vdboot`
- Network: systemd-networkd DHCP (automatic IP)
- Filesystem: ext4
- Partition table: GPT
