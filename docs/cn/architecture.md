# 项目架构

## 目录结构

```
vd-boot/
├── run.sh                          # 主入口脚本（build/qemu/list/clean）
├── boot.sh                         # GRUB 引导项安装脚本
├── README.md                       # 项目简介（英文）
├── README_CN.md                    # 项目简介（中文）
├── LICENSE                         # GPLv3 许可证
├── config/
│   ├── mirrors.conf                # 镜像源和版本配置
│   ├── initramfs-defaults.conf     # 各发行版默认 initramfs 工具
│   ├── dracut-vhdboot.conf         # dracut 构建配置
│   ├── mkinitcpio-kloop.conf       # mkinitcpio kloop 模式配置
│   └── mkinitcpio-vloop.conf       # mkinitcpio vloop 模式配置
├── lib/
│   ├── common.sh                   # 公共函数（日志、校验、版本等）
│   ├── disk.sh                     # 磁盘创建、分区、格式转换
│   └── chroot.sh                   # chroot 环境管理、initramfs 构建
├── boot/
│   ├── vhdmount-kloop.sh           # kloop/squashfs dracut 钩子脚本
│   ├── vhdmount-vloop.sh           # vloop/squashfs dracut 钩子脚本
│   ├── vhdmount-initramfs-tools.sh # initramfs-tools 钩子脚本
│   ├── mkinitcpio-install-vhdboot  # mkinitcpio install 钩子
│   └── mkinitcpio-hooks-vhdboot    # mkinitcpio runtime 钩子
├── grub/
│   └── grub.cfg                    # GRUB 配置示例（多格式、多模式）
├── distros/
│   ├── archlinux/build.sh          # Arch Linux 构建脚本
│   ├── ubuntu/build.sh             # Ubuntu 构建脚本
│   ├── debian/build.sh             # Debian 构建脚本
│   ├── deepin/build.sh             # Deepin 构建脚本
│   ├── fedora/build.sh             # Fedora 构建脚本
│   └── opensuse/build.sh           # OpenSUSE 构建脚本
├── docs/
│   ├── en/                         # 英文文档
│   └── CN/                         # 中文文档
└── output/                         # 默认构建输出目录
```

## 构建流程

完整的构建流程如下：

```
run.sh build <distro> [options]
  │
  ├─ 1. 参数解析和校验
  │     验证发行版、启动模式、磁盘类型、格式等参数
  │
  ├─ 2. 调用 distros/<distro>/build.sh
  │     │
  │     ├─ 2a. 创建磁盘镜像 (lib/disk.sh → create_disk)
  │     │      使用 qemu-img 创建指定格式和类型的虚拟磁盘
  │     │
  │     ├─ 2b. 分区和格式化 (lib/disk.sh → partition_and_mount)
  │     │      GPT 分区表 + ext4 文件系统
  │     │      losetup 挂载为 loop 设备
  │     │
  │     ├─ 2c. 安装基础系统
  │     │      Arch: tar 解压 bootstrap tarball
  │     │      Ubuntu/Debian/Deepin: debootstrap
  │     │      Fedora: dnf --installroot
  │     │      OpenSUSE: zypper --root
  │     │
  │     ├─ 2d. chroot 配置 (lib/chroot.sh)
  │     │      安装内核、网络配置、设置密码
  │     │      安装 vhdboot 钩子脚本
  │     │      构建 initramfs (dracut/mkinitcpio/mkinitramfs)
  │     │
  │     ├─ 2e. 复制引导文件
  │     │      vmlinuz + initramfs-vhdboot.img → output 目录
  │     │
  │     └─ 2f. 卸载和清理
  │            umount, losetup -d
  │
  └─ 3. 构建完成
        输出文件: output/<distro>-<boot>-<disk>.<fmt>
```

## 启动流程

```
GRUB 菜单选择 VHD 启动项
  │
  ├─ GRUB 加载 vmlinuz 和 initramfs-vhdboot.img
  │
  ├─ Linux 内核启动，解压 initramfs
  │
  ├─ initramfs 中的 vhdboot 钩子脚本执行
  │   ├─ dracut: /lib/dracut/hooks/pre-mount/10-vhdmount.sh
  │   ├─ mkinitcpio: /hooks/vhdboot
  │   └─ initramfs-tools: /scripts/init-premount/vhdboot
  │
  ├─ 钩子脚本处理:
  │   ├─ 解析内核参数 (kloop/vloop/squashfs)
  │   ├─ 通过 UUID 挂载宿主分区到 /host
  │   ├─ 挂载虚拟磁盘 (loop + kpartx/mapper)
  │   │   或挂载 SquashFS + tmpfs overlay
  │   └─ 挂载根文件系统到 $NEWROOT
  │
  └─ 系统正常启动（init → systemd）
```

## 模块说明

### run.sh

项目主入口，提供以下子命令：

- `build` — 构建单个镜像
- `build-all` — 批量构建所有组合
- `qemu` — QEMU 启动测试
- `list` — 列出支持的组合
- `clean` — 清理输出
- `version` — 显示版本

### boot.sh

GRUB 引导项管理脚本：

- `install` — 生成并安装 GRUB 配置到 `/etc/grub.d/45_vhdboot`，然后运行 `update-grub`
- `generate` — 仅生成 GRUB 配置片段到标准输出

### lib/common.sh

公共工具函数：

- 日志输出（info/warn/err/debug）
- 依赖检查
- 清理陷阱（trap）管理
- fstab 生成
- root 密码和网络配置

### lib/disk.sh

磁盘操作：

- `create_disk` — 使用 qemu-img 创建虚拟磁盘
- `partition_and_mount` — 分区（GPT + ext4）并挂载
- `unmount_disk` — 安全卸载
- `convert_format` — 格式转换
- `create_squashfs` — 创建 SquashFS 镜像

### lib/chroot.sh

chroot 环境管理：

- `prepare_chroot` / `cleanup_chroot` — 挂载/卸载 proc/sys/dev 等
- `run_chroot` — 在 chroot 中执行命令
- `install_vhdboot` — 安装 vhdboot 钩子到 initramfs
- `build_initramfs` — 构建包含 vhdboot 钩子的 initramfs
- `copy_boot_files_to_output` — 复制内核和 initramfs 到输出目录

### boot/ 目录

启动钩子脚本，会被安装到虚拟磁盘内的 initramfs 中：

- `vhdmount-kloop.sh` — kloop 和 squashfs 模式的 dracut pre-mount 钩子
- `vhdmount-vloop.sh` — vloop 和 squashfs 模式的 dracut pre-mount 钩子
- `vhdmount-initramfs-tools.sh` — initramfs-tools 的钩子（Ubuntu/Debian/Deepin）
- `mkinitcpio-install-vhdboot` — mkinitcpio install hook（Arch Linux）
- `mkinitcpio-hooks-vhdboot` — mkinitcpio runtime hook（Arch Linux）
