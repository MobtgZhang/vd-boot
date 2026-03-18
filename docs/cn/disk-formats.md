# 磁盘格式说明

vd-boot 支持多种虚拟磁盘格式，满足不同虚拟化平台和使用场景的需求。

## 格式对比

| 格式     | 扩展名      | 平台兼容                   | 磁盘类型          | 说明                                 |
| -------- | ----------- | -------------------------- | ----------------- | ------------------------------------ |
| VHD      | `.vhd`      | Hyper-V, VirtualBox, QEMU  | fixed / dynamic   | 经典虚拟硬盘格式，兼容性好           |
| VMDK     | `.vmdk`     | VMware, VirtualBox, QEMU   | fixed / dynamic   | VMware 原生格式                      |
| VDI      | `.vdi`      | VirtualBox, QEMU           | fixed / dynamic   | VirtualBox 原生格式                  |
| QCOW2    | `.qcow2`    | QEMU/KVM                   | fixed / dynamic   | QEMU 原生格式，支持快照和压缩        |
| VHDX     | `.vhdx`     | Hyper-V, QEMU              | fixed / dynamic   | VHD 的升级版，支持更大容量            |
| SquashFS | `.squashfs` | Linux 原生                 | —                 | 只读压缩文件系统，运行在 RAM 中       |

## 磁盘类型

### 固定大小（fixed）

- 创建时即分配全部磁盘空间
- 性能更好（无需动态分配）
- 占用空间等于设定大小
- GRUB loopback 可以解析，支持从 VHD 内部加载内核

### 动态大小（dynamic）

- 按需增长，初始文件很小
- 节省宿主机存储空间
- GRUB loopback 无法解析动态格式的 VHD/VMDK/VDI，**必须使用外部内核**
- 推荐用于大多数场景

## 各格式详细说明

### VHD（Virtual Hard Disk）

微软 Hyper-V 使用的虚拟磁盘格式。兼容性好，大部分虚拟化平台都支持。

```bash
# 固定大小 VHD
sudo ./run.sh build archlinux -f vhd -d fixed

# 动态大小 VHD
sudo ./run.sh build archlinux -f vhd -d dynamic
```

底层使用 `qemu-img create -f vpc` 创建。

### VMDK（Virtual Machine Disk）

VMware 的虚拟磁盘格式。

```bash
sudo ./run.sh build archlinux -f vmdk -d dynamic
```

- fixed 模式使用 `monolithicFlat` 子格式
- dynamic 模式使用 `monolithicSparse` 子格式

### VDI（VirtualBox Disk Image）

Oracle VirtualBox 的原生磁盘格式。

```bash
sudo ./run.sh build archlinux -f vdi -d dynamic
```

### QCOW2（QEMU Copy On Write）

QEMU/KVM 的原生格式，功能最丰富。

```bash
sudo ./run.sh build archlinux -f qcow2 -d dynamic
```

- 支持快照
- 支持压缩
- dynamic 模式使用 `preallocation=off`
- fixed 模式使用 `preallocation=full`

### VHDX（Virtual Hard Disk v2）

微软 Hyper-V 第二代虚拟磁盘格式，是 VHD 的升级版。

```bash
sudo ./run.sh build archlinux -f vhdx -d dynamic
```

- 最大支持 64TB 磁盘
- 更好的数据保护机制

### SquashFS

Linux 内核原生支持的只读压缩文件系统。

```bash
sudo ./run.sh build archlinux -f squashfs
```

- 使用 xz 压缩，镜像体积很小
- 启动时挂载到 RAM 中，使用 tmpfs overlay 提供可写层
- 重启后所有修改丢失（类似 Live CD）
- 始终需要外部内核和 initramfs
- 使用 `mksquashfs` 创建（需安装 `squashfs-tools`）

## 磁盘内部结构

所有 VHD/VMDK/VDI/QCOW2/VHDX 格式的磁盘内部结构一致：

```
GPT 分区表
└── 分区 1 (ext4, rootfs)
    ├── /boot/vmlinuz            # Linux 内核
    ├── /boot/initramfs-vhdboot.img  # initramfs（含 vhdboot 钩子）
    ├── /etc/fstab               # 文件系统表
    └── ...                      # 完整的 Linux 根文件系统
```

SquashFS 则直接是压缩后的根文件系统，不包含分区表。

## 格式转换

构建过程中，系统先在 raw 格式上完成所有操作（分区、安装系统），然后使用 `qemu-img convert` 转换到目标格式。也可以手动转换：

```bash
# RAW 转 VHD
qemu-img convert -f raw -O vpc -o subformat=dynamic input.img output.vhd

# RAW 转 QCOW2
qemu-img convert -f raw -O qcow2 -o preallocation=off input.img output.qcow2

# VHD 转 VMDK
qemu-img convert -f vpc -O vmdk -o subformat=monolithicSparse input.vhd output.vmdk
```
