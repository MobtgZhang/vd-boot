# 快速入门

本文档帮助你快速构建第一个可启动的虚拟磁盘镜像。

## 前置条件

- Linux 系统（推荐 Ubuntu/Debian/Fedora/Arch 作为构建主机）
- root 权限
- 基础依赖：`qemu-utils`、`parted`、`e2fsprogs`、`kpartx`、`wget` 或 `curl`

### 安装依赖

```bash
# Debian/Ubuntu
sudo apt install qemu-utils parted e2fsprogs kpartx wget

# Fedora
sudo dnf install qemu-img parted e2fsprogs kpartx wget

# Arch Linux
sudo pacman -S qemu-img parted e2fsprogs multipath-tools wget
```

## 第一个镜像：构建 Arch Linux VHD

```bash
# 克隆项目
git clone https://github.com/mobtgzhang/vd-boot.git
cd vd-boot

# 构建 Arch Linux 镜像（默认: kloop 启动、dynamic 磁盘、VHD 格式、16GB）
sudo ./run.sh build archlinux
```

构建完成后，镜像文件位于 `output/archlinux-kloop-dynamic.vhd`，同时会自动复制 `vmlinuz` 和 `initramfs-vhdboot.img` 到 `output/` 目录。

## 使用 QEMU 测试

```bash
# 使用内置 QEMU 启动（串口模式）
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd

# 图形界面启动，分配 4GB 内存
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -m 4096 -g

# SSH 连接（默认端口 2222，密码 vdboot）
ssh -p 2222 root@localhost
```

## 在真实机器上启动

将镜像文件和引导文件复制到目标磁盘上，然后配置 GRUB：

```bash
# 将镜像放到宿主机的某个分区（如 /vhd/）
sudo mkdir -p /vhd
sudo cp output/archlinux-kloop-dynamic.vhd /vhd/
sudo cp output/vmlinuz /vhd/
sudo cp output/initramfs-vhdboot.img /vhd/

# 使用 boot.sh 自动添加 GRUB 引导项
sudo ./boot.sh install -v /vhd/archlinux-kloop-dynamic.vhd -n "Arch Linux VHD"
```

重启后在 GRUB 菜单中选择即可进入 VHD 内的 Linux 系统。

## 更多示例

```bash
# 构建 Ubuntu，vloop 模式，VMDK 格式
sudo ./run.sh build ubuntu -b vloop -f vmdk

# 构建 Fedora，固定大小磁盘，32GB
sudo ./run.sh build fedora -d fixed -s 32

# 构建 Debian，SquashFS 格式（只读压缩，运行在 RAM 中）
sudo ./run.sh build debian -f squashfs

# 构建所有发行版的所有组合
sudo ./run.sh build-all
```

## 下一步

- [构建指南](build-guide.md) — 完整的构建选项说明
- [启动模式详解](boot-modes.md) — kloop、vloop、squashfs 的原理和区别
- [GRUB 配置](grub-config.md) — 启动引导的详细配置
- [发行版说明](distros.md) — 各发行版的特殊要求和注意事项
