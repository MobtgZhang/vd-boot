# 构建指南

## 基本用法

```bash
sudo ./run.sh build <发行版> [选项]
```

## 支持的发行版

| 发行版    | 构建依赖                                   | 默认 initramfs |
| --------- | ------------------------------------------ | -------------- |
| archlinux | tar, zstd                                  | mkinitcpio     |
| ubuntu    | debootstrap                                | mkinitramfs    |
| debian    | debootstrap                                | mkinitramfs    |
| deepin    | debootstrap                                | mkinitramfs    |
| fedora    | dnf                                        | dracut         |
| opensuse  | zypper（需要 OpenSUSE 主机或容器）          | dracut         |

## 构建选项

| 选项              | 说明                                                  | 默认值                              |
| ----------------- | ----------------------------------------------------- | ----------------------------------- |
| `-o, --output`    | 输出文件路径                                          | `output/<distro>-<boot>-<disk>.<fmt>` |
| `-s, --size`      | 磁盘大小（GB，范围 1-1024）                           | 16                                  |
| `-b, --boot`      | 启动模式：`kloop` / `vloop`                           | kloop                               |
| `-d, --disk`      | 磁盘类型：`fixed`（固定大小）/ `dynamic`（动态扩展）  | dynamic                             |
| `-f, --format`    | 输出格式：`vhd` / `vmdk` / `vdi` / `qcow2` / `vhdx` / `squashfs` | vhd                  |
| `-m, --initramfs` | initramfs 工具：`dracut` / `mkinitramfs` / `mkinitcpio` | 跟随发行版默认                    |

## 构建示例

### 单个镜像

```bash
# Arch Linux, kloop, 固定大小 32GB VHD
sudo ./run.sh build archlinux -o output/arch.vhd -s 32 -b kloop -d fixed -f vhd

# Ubuntu, vloop, 动态大小 VMDK
sudo ./run.sh build ubuntu -b vloop -d dynamic -f vmdk

# Fedora, dracut initramfs, 动态 VHD
sudo ./run.sh build fedora -m dracut -d dynamic

# Debian, QCOW2 格式
sudo ./run.sh build debian -f qcow2 -d dynamic

# Arch Linux, SquashFS（只读压缩镜像）
sudo ./run.sh build archlinux -f squashfs
```

### 批量构建

```bash
# 构建所有发行版 × kloop/vloop × fixed/dynamic 的 VHD
sudo ./run.sh build-all

# 仅构建指定发行版的所有组合
sudo ./run.sh build-all archlinux
sudo ./run.sh build-all debian
```

### 其他命令

```bash
# 列出所有支持的组合
./run.sh list

# 清理输出目录
./run.sh clean

# 查看版本
./run.sh version
```

## 版本配置

编辑 `config/mirrors.conf` 来配置发行版版本号：

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

所有发行版均默认从清华大学镜像源（mirrors.tuna.tsinghua.edu.cn）下载。

## 构建产物

构建完成后，`output/` 目录下会生成：

| 文件                      | 说明                            |
| ------------------------- | ------------------------------- |
| `<distro>-<boot>-<disk>.<fmt>` | 虚拟磁盘镜像文件           |
| `vmlinuz`                 | 内核文件（用于外部引导）        |
| `initramfs-vhdboot.img`   | initramfs 镜像（含 vhdboot 钩子） |

## 环境变量

| 变量         | 说明         | 默认值               |
| ------------ | ------------ | -------------------- |
| `OUTPUT_DIR` | 输出目录     | `./output`           |
| `WORKDIR`    | 构建临时目录 | `/tmp/vhdboot-build` |
| `VD_DEBUG`   | 调试输出     | `0`（关闭）          |
