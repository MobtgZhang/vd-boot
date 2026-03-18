# 发行版说明

## Arch Linux

- **构建依赖**：`tar`、`zstd`
- **默认 initramfs**：mkinitcpio
- **软件源**：清华大学 Arch Linux 镜像
- **构建方式**：下载 bootstrap tarball 并解压到虚拟磁盘

```bash
sudo ./run.sh build archlinux
```

Arch Linux 使用滚动更新模型，构建时获取的是最新版本。

## Ubuntu

- **构建依赖**：`debootstrap`
- **默认 initramfs**：mkinitramfs（initramfs-tools）
- **软件源**：清华大学 Ubuntu 镜像
- **构建方式**：使用 debootstrap 从镜像源安装

```bash
sudo ./run.sh build ubuntu
```

在 `config/mirrors.conf` 中配置版本：

```bash
# noble(24.04), jammy(22.04), focal(20.04)
UBUNTU_CODENAME="noble"
```

## Debian

- **构建依赖**：`debootstrap`
- **默认 initramfs**：mkinitramfs（initramfs-tools）
- **软件源**：清华大学 Debian 镜像
- **构建方式**：使用 debootstrap 从镜像源安装

```bash
sudo ./run.sh build debian
```

在 `config/mirrors.conf` 中配置版本：

```bash
# bookworm(12), trixie(13), bullseye(11)
DEBIAN_CODENAME="bookworm"
```

## Fedora

- **构建依赖**：`dnf`
- **默认 initramfs**：dracut
- **软件源**：清华大学 Fedora 镜像
- **构建方式**：使用 dnf 从镜像源安装

```bash
sudo ./run.sh build fedora
```

在 `config/mirrors.conf` 中配置版本：

```bash
# 41, 40, 39
FEDORA_RELEASE="41"
```

## Deepin

- **构建依赖**：`debootstrap`
- **默认 initramfs**：mkinitramfs（initramfs-tools）
- **软件源**：清华大学 Deepin 镜像
- **基础系统**：基于 Debian，使用 Debian bookworm 作为基础

```bash
sudo ./run.sh build deepin
```

构建使用 Debian bookworm 作为基础系统；如果 Deepin 镜像源可用则使用 Deepin 软件包，否则回退到 Debian。

在 `config/mirrors.conf` 中配置版本：

```bash
# apricot(20.x), beige(23.x)
DEEPIN_CODENAME="apricot"
```

## OpenSUSE

- **构建依赖**：`zypper`
- **默认 initramfs**：dracut
- **软件源**：清华大学 OpenSUSE 镜像
- **特殊要求**：**必须在 OpenSUSE 环境中构建**（zypper 仅在 OpenSUSE 上可用）

```bash
sudo ./run.sh build opensuse
```

如果主机不是 OpenSUSE，可使用 Docker 容器：

```bash
sudo docker run --privileged -v $(pwd):/build -w /build opensuse/leap \
  /build/run.sh build opensuse -o /build/output/opensuse.vhd
```

在 `config/mirrors.conf` 中配置版本：

```bash
# 15.6, 15.5
OPENSUSE_LEAP="15.6"
```

## 跨发行版使用 initramfs 工具

每个发行版有默认的 initramfs 工具，但可以通过 `-m` 参数覆盖：

```bash
# Arch Linux 使用 dracut 替代 mkinitcpio
sudo ./run.sh build archlinux -m dracut

# Ubuntu 使用 dracut 替代 mkinitramfs
sudo ./run.sh build ubuntu -m dracut
```

注意：跨发行版使用 initramfs 工具需要目标系统中安装了对应工具。

## 通用配置

所有发行版构建完成后：

- 默认 root 密码：`vdboot`
- 网络配置：systemd-networkd DHCP（自动获取 IP）
- 文件系统：ext4
- 分区表：GPT
