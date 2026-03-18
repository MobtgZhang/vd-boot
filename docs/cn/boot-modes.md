# 启动模式详解

vd-boot 支持三种启动模式，每种模式使用不同的方式从虚拟磁盘文件引导 Linux。

## 模式概览

| 模式     | 原理                        | 读写   | 适用格式                       | 说明                         |
| -------- | --------------------------- | ------ | ------------------------------ | ---------------------------- |
| kloop    | loop + kpartx 映射分区      | 读写   | VHD, VMDK, VDI, QCOW2, VHDX   | 通用性最好，推荐默认使用     |
| vloop    | loop + device-mapper 分区   | 读写   | VHD, VMDK, VDI, QCOW2, VHDX   | 与 kloop 类似，分区映射方式不同 |
| squashfs | squashfs + tmpfs overlay    | 只读+覆写 | SquashFS                       | 运行在 RAM 中，重启后丢失修改 |

## kloop 模式

kloop 模式使用 `losetup` 将虚拟磁盘文件挂载为 loop 设备，然后使用 `kpartx` 创建分区映射设备（如 `/dev/mapper/loop0p1`），最后挂载到根目录。

### 引导流程

```
GRUB 加载内核和 initramfs
  ↓
initramfs 中的 vhdmount-kloop.sh 被执行
  ↓
挂载宿主分区到 /host（通过 UUID 查找）
  ↓
losetup 挂载 /host/<vhd路径> 为 loop 设备
  ↓
kpartx 创建分区映射 /dev/mapper/loop0p1
  ↓
mount /dev/mapper/loop0p1 到根目录
  ↓
系统正常启动
```

### 内核参数

```
root=UUID=<宿主分区UUID> kloop=<vhd路径> kroot=/dev/mapper/loop0p1
```

- `kloop=` — 虚拟磁盘文件在宿主分区上的路径
- `kroot=` — VHD 内的根分区设备（默认第一个分区 `loop0p1`）
- `kloopfstype=` — 可选，VHD 内文件系统类型（默认自动检测，通常为 ext4）
- `hostfstype=` — 可选，宿主分区文件系统类型（默认自动检测）
- `klvm=` — 可选，如果 VHD 内使用 LVM，指定卷组名称

### LVM 支持

kloop 支持 VHD 内包含 LVM 的情况：

```
root=UUID=<uuid> kloop=/vhd/arch-lvm.vhd kroot=/dev/mapper/vg0-root klvm=vg0
```

## vloop 模式

vloop 模式与 kloop 类似，但使用不同的分区映射方式。vloop 直接通过 loop 设备的分区映射 (`/dev/mapper/loop0pN`) 访问 VHD 内的分区。

### 内核参数

```
root=UUID=<宿主分区UUID> vloop=<vhd路径> vlooppart=p1
```

- `vloop=` — 虚拟磁盘文件路径
- `vlooppart=` — 分区号：`p1`=第一分区，`p2`=第二分区，以此类推
- `vloopfstype=` — 可选，VHD 内文件系统类型
- `hostfstype=` — 可选，宿主分区文件系统类型

## SquashFS 模式

SquashFS 模式将整个根文件系统压缩为只读的 SquashFS 镜像，启动时挂载到内存中，使用 tmpfs overlay 提供可写层。这类似于 Live CD 的运行方式——所有修改在重启后丢失。

### 引导流程

```
GRUB 加载内核和 initramfs
  ↓
initramfs 中的 hook 脚本被执行
  ↓
挂载宿主分区到 /host（只读）
  ↓
mount -t squashfs /host/<squashfs路径> /run/vdboot/squashfs（只读）
  ↓
mount -t tmpfs /run/vdboot/tmpfs（可写，占用内存 50%）
  ↓
mount -t overlay（lower=squashfs, upper=tmpfs）到根目录
  ↓
系统在 RAM 中运行
```

### 内核参数

```
root=UUID=<宿主分区UUID> squashfs=<squashfs路径>
```

### 特点

- 镜像文件非常小（使用 xz 压缩）
- 系统完全运行在 RAM 中，速度快
- 重启后所有修改丢失（无持久化）
- 始终需要外部内核和 initramfs（无法从 SquashFS 内加载）
- 建议分配足够内存（至少 2GB，推荐 4GB+）

## 内核加载方式

虚拟磁盘启动需要 GRUB 加载内核（vmlinuz）和 initramfs。有两种加载方式：

| 方式                        | 适用于            | 说明                                                |
| --------------------------- | ----------------- | --------------------------------------------------- |
| **外部加载**（默认）         | 所有格式和类型     | vmlinuz 和 initramfs-vhdboot.img 与 VHD 放在同一目录 |
| **内部加载** (`--inside`)    | 仅固定大小 VHD    | 从 VHD 内部 /boot 加载，不需要额外文件               |

动态大小的 VHD/VMDK/VDI/QCOW2/VHDX 无法被 GRUB 的 loopback 解析，因此必须使用外部内核。构建过程会自动将 `vmlinuz` 和 `initramfs-vhdboot.img` 复制到输出目录。

## initramfs 工具

vd-boot 在构建 initramfs 时注入了启动钩子脚本。支持三种 initramfs 构建工具：

| 工具        | 发行版默认使用          | 钩子安装位置                                             |
| ----------- | ---------------------- | -------------------------------------------------------- |
| dracut      | Fedora, OpenSUSE       | `/lib/dracut/hooks/pre-mount/` 及 dracut module          |
| mkinitcpio  | Arch Linux             | `/usr/lib/initcpio/install/vhdboot` 和 `hooks/vhdboot`   |
| mkinitramfs | Ubuntu, Debian, Deepin | `/usr/share/initramfs-tools/scripts/init-premount/vhdboot` |

可以通过 `-m` 参数覆盖默认工具，但通常建议使用发行版自带的默认工具。
