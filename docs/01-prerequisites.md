# 1. 硬件、BIOS 和宿主机

以下 BIOS 菜单位置以 ASRock B460M Pro4S/ac P1.40 为参考，其他版本名称可能不同。开启 Intel Virtualization Technology（VT-x）、VT-d 和 Above 4G Decoding，使用 UEFI 启动并关闭 CSM。实测只确认 Above 4G 已开启，没有找到 C.A.M. / Re-Size BAR 菜单，也没有为了这个菜单刷 BIOS。

本例的 BAR 调整通过 Linux PCI `resource1_resize` 完成，前提是内核暴露接口、显卡支持对应大小且固件预留足够高位 MMIO。菜单不存在不等于这台机器不能调整 BAR；另一块主板没有接口或空间时，也不能靠复制脚本解决。

## VFIO 绑定

在 Unraid **Tools → System Devices** 找到 NVIDIA GPU 及同卡 HDMI 音频，勾选在启动时绑定 VFIO；重启宿主机后检查。不要把宿主机仍在使用的唯一显卡直接交给 VM。若设备目前供其他 VM 或容器使用，先正常停止使用它的任务。

在 Unraid 终端执行只读检查：

```bash
lspci -Dnnk | less
find /sys/kernel/iommu_groups/ -type l | sort
virsh list --all
```

实测 GPU / 音频 PCI ID 为 `10de:2504` / `10de:228e`。BDF、IOMMU 组号由你的机器决定，不能照抄组号。本仓库模板中的 BDF 占位符也必须替换。显卡和音频都应显示 `Kernel driver in use: vfio-pci`，同组中的其他设备必须适合一并直通或不被宿主机占用。没有实际必要时不要启用 ACS override。

本次显卡接着物理显示器。无人值守场景可另行测试假负载，但本记录没有验证其 EDID、分辨率或冷启动行为。

## 依赖与存储

配置生成工具只需要 Python 3.10+ 标准库。在 Windows 可以使用 `py -3`；没有 `py` 时用自己的 Python 路径替换。Unraid 的镜像构建与 BAR 脚本需要 root、Bash、`sgdisk`、`mkfs.vfat`、`losetup`、`mount`、`realpath`、`flock`、`fuser`、`lspci`、`qemu-img`。先用 `command -v` 检查；缺失时从适配当前 Unraid 版本的软件来源安装，不随意升级宿主机核心库。

示例目录（自行选择实际存储池和路径）：

```text
/mnt/user/domains/macos15/
├── efi/OpenCore.raw       # 512MiB，GPT + FAT32 ESP，单独可写引导盘
├── media/Recovery.img    # 临时恢复系统，装完移除
├── media/Installer.raw   # 32GiB 临时完整安装盘
├── media/Delivery.raw    # 可选：装有完整 pkg 和 Payload.cpio 的传递盘
├── vdisk1.qcow2          # 160GiB 系统盘
└── nvram/VARS.fd         # 每台 VM 独立的 OVMF 变量文件
```

创建文件时先检查路径和可用空间，禁止覆盖已有 VM 磁盘。选择 `br0` 或自己的桥接网卡，给 macOS 分配可从你的电脑访问的地址。实际密码只在 macOS 设置界面输入，不写进 XML、脚本或 README。

## CPU 与内存

宿主机主要空闲时，这台 10900K 可以给 VM **1 socket × 10 cores × 2 threads = 20 vCPU**，内存 16GiB。本例未隔离宿主机 CPU、未锁定全部核心；宿主机仍可调度自己的任务。

使用 `host-passthrough`、`cache passthrough`，同时启用 OpenCore `ProvideCurrentCpuInfo`。QEMU 10.2.3 按 APIC 地址位数计算部分 CPUID 拓扑，因此非 2 的幂的 10 核会在部分查询中显示 16 核 / 32 线程；macOS 的 `hw.physicalcpu` / `hw.logicalcpu` 实测为 10 / 20。不要把显示值当作额外算力。此 ES CPU 的营销名称仍为 Unknown；无需为改名字继续叠加 CPU 伪装。

参考：[QEMU 10.2.3 CPU 拓扑代码](https://github.com/qemu/qemu/blob/v10.2.3/target/i386/cpu.c)、[OpenCore 1.0.5 CPU 类型](https://github.com/acidanthera/OpenCorePkg/blob/1.0.5/Include/Apple/IndustryStandard/AppleSmBios.h)。
