# GRUB 配置指南

本文档说明如何配置 GRUB 从虚拟磁盘文件启动 Linux。

## 使用 boot.sh（推荐）

`boot.sh` 可以自动生成 GRUB 引导配置并安装到系统中。

### 安装引导项

```bash
# 添加 kloop 引导项（需要 root）
sudo ./boot.sh install -v /vhd/arch.vhd -n "Arch Linux VHD"

# 添加 vloop 引导项
sudo ./boot.sh install -v /vhd/ubuntu.vhd -b vloop -n "Ubuntu VHD"

# QCOW2 格式
sudo ./boot.sh install -v /vhd/arch.qcow2 -n "Arch Linux QCOW2"

# VHDX 格式
sudo ./boot.sh install -v /vhd/arch.vhdx -n "Arch Linux VHDX"

# SquashFS 格式（自动检测启动模式）
sudo ./boot.sh install -v /vhd/rootfs.squashfs -n "Arch Linux SquashFS"

# 从固定大小 VHD 内部加载内核
sudo ./boot.sh install -v /vhd/arch-fixed.vhd -I -n "Arch Linux (Fixed)"

# 安装 GRUB 到其他磁盘（例如 U 盘 /dev/sdb）
sudo ./boot.sh install -v /vhd/arch.vhd -g -t /dev/sdb
```

### 仅生成配置（不安装）

```bash
./boot.sh generate -v /vhd/fedora.vhd -b kloop
```

### boot.sh 选项

| 选项              | 说明                                             |
| ----------------- | ------------------------------------------------ |
| `-v, --vhd`      | 磁盘镜像路径                                     |
| `-b, --boot`     | 启动模式：`kloop` / `vloop` / `squashfs`         |
| `-n, --name`     | GRUB 菜单显示名称                                |
| `-p, --part`     | vloop 分区号：`p1`/`p2`/`p3`...                  |
| `-k, --kernel`   | 内核路径（默认与 VHD 同目录的 vmlinuz）           |
| `-i, --initrd`   | initrd 路径（默认与 VHD 同目录的 initramfs-vhdboot.img） |
| `-I, --inside`   | 从 VHD 内部加载内核（仅固定大小 VHD）             |
| `-g, --install-grub` | 安装 GRUB 到指定磁盘（配合 `-t` 使用）       |
| `-t, --target`   | GRUB 安装目标设备（如 `/dev/sdb`）                |

## 手动配置 GRUB

如果不使用 `boot.sh`，可以手动编写 GRUB 配置。

### 文件放置

将以下三个文件放到同一目录（如 `/vhd/`）：

```
/vhd/
├── archlinux-kloop-dynamic.vhd   # 虚拟磁盘
├── vmlinuz                        # 内核
└── initramfs-vhdboot.img          # initramfs
```

### kloop 模式配置

```
menuentry 'Arch Linux VHD (kloop)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set vhdfile="$vhddir/arch-kloop-dynamic.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} kloop=$vhdfile kroot=/dev/mapper/loop0p1
    initrd $vhddir/initramfs-vhdboot.img
}
```

### vloop 模式配置

```
menuentry 'Arch Linux VHD (vloop)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set vhdfile="$vhddir/arch-vloop-dynamic.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} vloop=$vhdfile vlooppart=p1
    initrd $vhddir/initramfs-vhdboot.img
}
```

### SquashFS 模式配置

```
menuentry 'Arch Linux SquashFS (RAM overlay)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set squashfile="$vhddir/arch.squashfs"
    search --no-floppy -f --set=root $squashfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} squashfs=$squashfile
    initrd $vhddir/initramfs-vhdboot.img
}
```

### 从 VHD 内部加载内核（固定大小 VHD）

```
menuentry 'Arch Linux VHD (kloop, internal)' --class arch --class gnu-linux {
    set vhdfile="/vhd/arch-kloop-fixed.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    insmod part_gpt
    insmod part_msdos
    insmod ext2
    loopback lp0 $vhdfile
    linux (lp0,1)/boot/vmlinuz root=UUID=${uuid} kloop=$vhdfile kroot=/dev/mapper/loop0p1
    initrd (lp0,1)/boot/initramfs-vhdboot.img
}
```

### LVM 分区

```
menuentry 'Arch Linux VHD (kloop+LVM)' --class arch --class gnu-linux {
    set vhddir="/vhd"
    set vhdfile="$vhddir/arch-lvm.vhd"
    search --no-floppy -f --set=root $vhdfile
    probe -u --set=uuid ${root}

    linux $vhddir/vmlinuz root=UUID=${uuid} kloop=$vhdfile kroot=/dev/mapper/vg0-root klvm=vg0
    initrd $vhddir/initramfs-vhdboot.img
}
```

## GRUB 菜单可见性

`boot.sh install` 会自动检查并修复以下配置，确保 GRUB 菜单可见：

- 将 `GRUB_TIMEOUT_STYLE=hidden` 修改为 `GRUB_TIMEOUT_STYLE=menu`
- 将 `GRUB_TIMEOUT=0` 修改为 `GRUB_TIMEOUT=5`

这些配置位于 `/etc/default/grub`。

## 更多 GRUB 配置示例

项目中 `grub/grub.cfg` 文件包含了多种格式和模式的完整 GRUB 配置示例，包括 VHD、VMDK、VDI、QCOW2、VHDX、SquashFS 等。
