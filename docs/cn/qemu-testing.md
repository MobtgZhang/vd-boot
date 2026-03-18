# QEMU 测试指南

vd-boot 内置了 QEMU 启动功能，可以快速测试构建的虚拟磁盘镜像。

## 前置条件

```bash
# Debian/Ubuntu
sudo apt install qemu-system-x86

# Fedora
sudo dnf install qemu-system-x86

# Arch Linux
sudo pacman -S qemu-system-x86
```

UEFI 启动还需要 OVMF 固件：

```bash
# Debian/Ubuntu
sudo apt install ovmf

# Fedora
sudo dnf install edk2-ovmf

# Arch Linux
sudo pacman -S edk2-ovmf
```

## 基本用法

```bash
sudo ./run.sh qemu <镜像文件> [选项]
```

## 选项

| 选项            | 说明                          | 默认值 |
| --------------- | ----------------------------- | ------ |
| `-m, --memory`  | 内存大小（MB）                | 2048   |
| `-c, --cpus`    | CPU 数量                      | 2      |
| `-k, --kernel`  | 外部内核路径                  | 自动检测 |
| `-i, --initrd`  | 外部 initrd 路径              | 自动检测 |
| `-a, --append`  | 额外内核启动参数              | —      |
| `-e, --efi`     | 使用 UEFI 启动（需要 OVMF）  | 关闭   |
| `-g, --graphic` | 图形界面显示                  | 关闭（串口） |
| `-p, --port`    | SSH 转发端口                  | 2222   |

## 示例

### 基本测试（串口模式）

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd
```

退出方式：`Ctrl-A X`

### 图形界面 + 更多资源

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -m 4096 -c 4 -g
```

### UEFI 启动

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -e
```

### SSH 连接

QEMU 默认将虚拟机的 22 端口转发到宿主机的 2222 端口：

```bash
# 启动后，在另一个终端连接
ssh -p 2222 root@localhost
# 密码: vdboot
```

自定义 SSH 端口：

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd -p 3333
ssh -p 3333 root@localhost
```

### 指定外部内核

```bash
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd \
  -k output/vmlinuz \
  -i output/initramfs-vhdboot.img
```

### 测试不同格式

```bash
# QCOW2
sudo ./run.sh qemu output/archlinux-kloop-dynamic.qcow2

# VMDK
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vmdk

# SquashFS（需要外部内核）
sudo ./run.sh qemu output/arch.squashfs \
  -k output/vmlinuz \
  -i output/initramfs-vhdboot.img
```

## 格式与 QEMU 映射

| 文件扩展名   | QEMU 格式  |
| ------------ | ---------- |
| `.vhd`       | vpc        |
| `.vmdk`      | vmdk       |
| `.vdi`       | vdi        |
| `.qcow2`     | qcow2      |
| `.vhdx`      | vhdx       |
| `.squashfs`  | 特殊处理   |
| `.img`/`.raw`| raw        |

SquashFS 文件无法直接作为 QEMU 磁盘使用，vd-boot 会自动创建临时 ext4 载体磁盘，将 SquashFS 文件放入其中后启动。

## 自动内核检测

如果不指定 `-k` 和 `-i`，QEMU 启动命令会自动检测镜像文件同目录下的 `vmlinuz` 和 `initramfs-vhdboot.img`。如果找到则使用外部内核启动，否则尝试从磁盘直接启动。

## 故障排查

- **启动卡住**：尝试增加内存 `-m 4096`，特别是 SquashFS 模式
- **黑屏无输出**：串口模式下请检查是否正确使用了 `console=ttyS0` 参数
- **无法 SSH**：确认端口转发是否正确，虚拟机内 sshd 是否启动
- **UEFI 启动失败**：确认已安装 OVMF 固件包
