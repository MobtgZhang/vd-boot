# vd-boot

[English](README.md)

从清华大学镜像源下载并构建可启动的 VHD/VMDK/VDI/QCOW2/VHDX/SquashFS 虚拟磁盘文件，支持通过 kloop 或 vloop 模式直接从虚拟磁盘引导 Linux。

## 特性

- **发行版**：Arch Linux、Ubuntu、Fedora、Debian、Deepin、OpenSUSE
- **启动模式**：kloop、vloop、SquashFS（RAM overlay）
- **磁盘类型**：固定大小（fixed）、动态大小（dynamic）
- **输出格式**：VHD、VMDK、VDI、QCOW2、VHDX、SquashFS
- **镜像源**：清华大学镜像（mirrors.tuna.tsinghua.edu.cn）
- **QEMU 测试**：内置 QEMU 启动，支持串口和图形模式
- **GRUB 配置**：自动生成并安装 GRUB 引导项

## 快速开始

```bash
# 安装依赖（Debian/Ubuntu）
sudo apt install qemu-utils parted e2fsprogs kpartx wget

# 构建 Arch Linux 虚拟磁盘
sudo ./run.sh build archlinux

# 用 QEMU 测试
sudo ./run.sh qemu output/archlinux-kloop-dynamic.vhd

# 添加 GRUB 引导项到宿主机
sudo ./boot.sh install -v /vhd/archlinux-kloop-dynamic.vhd -n "Arch Linux VHD"
```

## 常用命令

```bash
sudo ./run.sh build <发行版> [选项]    # 构建单个镜像
sudo ./run.sh build-all                # 构建所有组合
sudo ./run.sh qemu <镜像> [选项]       # QEMU 启动测试
./run.sh list                          # 列出支持的组合
./run.sh clean                         # 清理输出目录
```

## 目录结构

```
vd-boot/
├── run.sh              # 主入口脚本
├── boot.sh             # GRUB 引导项安装脚本
├── config/             # 镜像源、版本和 initramfs 配置
├── lib/                # 公共函数库（磁盘、chroot、通用）
├── boot/               # initramfs 启动钩子脚本
├── grub/               # GRUB 配置示例
├── distros/            # 各发行版构建脚本
├── docs/               # 文档（en / CN）
└── output/             # 默认输出目录
```

## 文档

| 文档 | 说明 |
| ---- | ---- |
| [快速入门](docs/CN/getting-started.md) | 安装依赖、构建第一个镜像、启动测试 |
| [构建指南](docs/CN/build-guide.md) | 完整构建选项、批量构建、版本配置 |
| [启动模式详解](docs/CN/boot-modes.md) | kloop、vloop、SquashFS 的原理和区别 |
| [GRUB 配置](docs/CN/grub-config.md) | boot.sh 用法和手动 GRUB 配置 |
| [磁盘格式说明](docs/CN/disk-formats.md) | VHD/VMDK/VDI/QCOW2/VHDX/SquashFS 对比 |
| [发行版说明](docs/CN/distros.md) | 各发行版特殊要求和注意事项 |
| [QEMU 测试](docs/CN/qemu-testing.md) | QEMU 启动选项和故障排查 |
| [项目架构](docs/CN/architecture.md) | 目录结构、构建流程、模块说明 |

## 许可证

GNU General Public License v3.0
