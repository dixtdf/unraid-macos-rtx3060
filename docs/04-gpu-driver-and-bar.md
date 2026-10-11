# 4. RTX 3060、BAR1 与 NullMoth 驱动

先确认 macOS 已安装、SSH 与**客户机** VNC 都能连接，并建立[冷备份](07-backup-and-publishing.md)。后续需要多次正常关机，不能在 QEMU 正持有显卡时解绑或调整 BAR。

## BAR1 从 256MiB 调整到 8GiB

本次 256MiB BAR1 下出现较长的初始化等待和分配失败；调整到 8GiB 后完成 Metal 验收。12GB 显存与 8GiB BAR 映射窗口是不同概念，窗口不要求等于显存总量。

先在 Unraid 找到实际 BDF，确认两个功能均绑定 `vfio-pci`。复制 `templates/bar.example.conf` 到本地工作副本，填入 VM 名称、GPU 和音频 BDF。脚本固定检查 `10de:2504 / 10de:228e`，不要为了其他型号把检查直接删除。

在 VM 已正常关闭时：

```bash
install -o root -g root -m 600 /path/to/bar.conf /etc/macos-rtx-bar.conf
virsh domstate macos15
bash scripts/unraid/resize-bar.sh /etc/macos-rtx-bar.conf
lspci -Dvv -s YOUR_GPU_BDF
```

脚本检查 VFIO group / cdev 是否被进程占用、BAR1 是否支持 8GiB；将 GPU 与音频都解绑，写入 resize 值 `13`，确认大小 `8589934592` 字节，再重新绑定 VFIO。退出或中断时也尝试重新绑定。

Linux 的大小编码是 `2^(20+n)` 字节，`n=13` 为 8GiB。读取 `resource1_resize` 得到的是支持大小的位掩码，**读取结果并不是当前大小编码**。当前大小由 `resource` 的第 2 行起止地址计算。

原理参考：[Linux PCI sysfs ABI](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-bus-pci)。如果接口缺失、未广告 8GiB、MMIO 分配失败，先保留故障信息并检查 BIOS / 内核 / PCI 拓扑。脚本不会为你刷 BIOS、启用 ACS 或强制停止其他任务。执行期间不要启动使用这张卡的其他 VM / 容器。

## 每次启动 VM 前自动调整

Unraid 重启后 `/etc` 与运行环境会重建，而 BAR 大小也可能恢复默认。本例把脚本和配置保留在 flash，再在启动时复制到内存文件系统。flash 通常为 FAT，不能依赖其 `chmod 600`；真正被 root 脚本读取的配置是 `/etc` 中权限受限的副本。

先检查现有 `/etc/libvirt/hooks/qemu` 与 `qemu.d`，不要覆盖 Unraid 或其他插件的主钩子。libvirt 支持 `qemu.d` 时，添加独立文件：

```bash
mkdir -p /boot/config/macos-rtx /etc/libvirt/hooks/qemu.d
cp /path/to/bar.conf /boot/config/macos-rtx/bar.conf
cp scripts/unraid/resize-bar.sh /boot/config/macos-rtx/resize-bar.sh
cp scripts/unraid/qemu-bar-hook.sh /boot/config/macos-rtx/qemu-bar-hook.sh
install -m 600 /boot/config/macos-rtx/bar.conf /etc/macos-rtx-bar.conf
install -m 755 /boot/config/macos-rtx/resize-bar.sh /usr/local/sbin/macos-rtx-resize-bar
install -m 755 /boot/config/macos-rtx/qemu-bar-hook.sh /etc/libvirt/hooks/qemu.d/50-macos-rtx-bar
```

在 `/boot/config/go` 中保留现有内容，增加上面最后三个 `install` 命令及创建 qemu.d 的命令，使其在 VM 自动启动之前完成。若 VM 管理服务已启动但首次添加钩子未被识别，安排全部 VM 停止后重启宿主机验证；不要为加载钩子在其他 VM 运行中重启 libvirt。

钩子只处理配置中的一个 VM，且仅在 `prepare begin` 时运行。钩子中不能再执行 `virsh` 等 libvirt 调用，否则可能死锁，见 [libvirt hooks 官方说明](https://libvirt.org/hooks.html)。安装后先手动启动一次并确认 BAR1 为 8GiB，再启用无人值守自动启动。**通用化钩子的冷启动持久性需要在你的服务器验证**。

## 驱动配置与直通

把 `local/gpu/config.plist` 写入真正的 EFI 引导盘。libvirt 配置加入 GPU 和音频两个 `<hostdev>`；应包含足够的 PCIe root port、64 位 MMIO 和独立 OVMF NVRAM。模板保留实测 Q35 拓扑，使用该 Unraid 的 `pc-q35-10.2` 和 pure EFI OVMF。不要复制物理机的显卡 ROM 路径或随意添加 ROM 文件；本例没有加载外部 vBIOS。

安装驱动时可以暂时保留虚拟显示器辅助操作：将已生成的 GPU XML 中 `<video>` 暂时恢复为 install XML 的 Cirrus 节点，加入 install XML 的 VNC graphics 节点，磁盘保持仅 EFI / 系统盘。GPU 驱动接管后虚拟显示器可能黑屏，操作通过 SSH 或客户机 VNC 完成。

最终切回仓库生成的 GPU XML：

```xml
<video><model type="none"/></video>
```

移除虚拟 VNC `<graphics>`，仅保留 GPU + 音频直通。模板 USB 是 `qemu-xhci ports=4`，对应 8 个逻辑端口；曾把值盲目增到 15 后丢失输入，因此不要照物理 USB 数量修改此值。

## 安装固定驱动包

本仓库此次选择 **NullMoth 1.9.0 的 H.264 硬编路径**；1.13.0 已完成独立验收，但仍不为 RTX 3060 注册硬编。本轮仅回退驱动、GlideBeam NVENC 生产自测、Windows 实际传输、完整冷备与冷启动均完成；OpenCL 参数设置失败、HEVC 硬编像素失败、部分 Mac H.264 硬解输入有明显误差，见[本轮记录](11-driver-upgrade-1.13.0.md)。下一次更新先读[通用流程](12-driver-upgrade-runbook.md)，不根据版本号自动更换功能。

已有驱动的机器使用本轮审查过的官方 **1.13.0 安装器 `--payload` + 完整原始 1.9.0 payload**，保留新版 `ditto` 备份及正确的 VERSION marker。它只安装指定驱动，不恢复旧 VDisk，也不改 EFI、SIP、boot-args、身份或用户数据；需要预先建立完整冷备。

| 固定官方资产 | 大小 | SHA256 | 本轮包内 manifest |
| --- | --- | --- | --- |
| [1.9.0 payload](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.9.0/nullmoth-nvidia-1.9.0.tar.gz) | 269295455 字节 | `573546d77d6999ef4f5a808b036da39fa99b4856909f02c7b95adef017a240f2` | 53 项，Library 42 项 |
| [1.13.0 安装器来源](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.13.0/nullmoth-nvidia-1.13.0.tar.gz) | 269301262 字节 | `994970b1bba53e3ae8d7f500ef27b25cae8bc6818abc112d35230a58e6882fdf` | 54 项，Library 43 项 |

在 macOS 私有工作目录准备两包，与上表完整摘要和官方 digest 比较。先审查归档路径，再分别解压到两个新目录，保持原始 payload 和 manifest 未改；核对两包的全清单。下面示例假定已审查并准备好对应目录：

```bash
set -euo pipefail
installer_root=/path/to/installer-1.13.0/pkgroot
payload_root=/path/to/payload-1.9.0/pkgroot
(cd "$installer_root" && shasum -a 256 -c SHA256SUMS)
(cd "$payload_root" && shasum -a 256 -c SHA256SUMS)
sudo env CHECK=1 /bin/bash "$installer_root/install.sh" --payload "$payload_root"
# 预检失败时先处理；安装后确认退出码、旧组件备份与 KC 发布成功。
sudo /bin/bash "$installer_root/install.sh" --payload "$payload_root"
sudo shutdown -r now
```

新版安装器从指定 payload 的 `VERSION` 写入 `/Library/NullMoth/driver-version`；重启后仍需核对原始 1.9.0 的 42 项 Library payload 与运行中的组件，不能只看 marker。1.10.0～1.13.0 直接安装其各自 payload 时，RTX 3060 的 NVENC 仍不可用，手动 tar 安装不会绕过源码门控。

系统若要求允许内核扩展，在“隐私与安全性”允许并再重启。安装失败时保存私有日志与安装器给出的备份目录，先解决失败，不要继续切到纯直通画面。旧 1.9.0 安装器的 `cp -Rp` 在已有 Vulkan 符号链接时可能失败；不能删除当前用户数据或改写原始 payload 来掩盖备份问题。

四个 kext 安装到 `/Library/Extensions`，从辅助内核集合加载；**不要再注入到 EFI/OC/Kexts**。Metal 插件在 `/Library/GPUBundles/NVMTLDriver.bundle`。主 kext 的 CFBundleVersion 显示 `0.1` 不等于装错包，包版本应以下载资产、摘要、实际组件清单和准确 marker 一并判定。1.13.0 tar 没有包含源码中的 `NMHDA` / `NMIntelFB`，不能据新版号宣称 HDMI / DP 音频已修复。

若 PCI / framebuffer 已识别，但原生 Metal 枚举仍没有 NVIDIA 设备，先检查驱动日志、加载情况、`WindowServerMetalPluginName` 等注册属性；这次排查中使用过 `sudo sysctl -w debug.nvaccelfb=1` 触发注册。该 sysctl 是驱动内部接口，不是所有版本通用的安装步骤。先验证一次是否解决，再检查重启后自动注册状态，不要未经验证永久循环写入或反复重启 WindowServer。

驱动升级 / 降级、macOS 更新、改变显示器或刷新率后，重新完成[验收](06-validation-and-troubleshooting.md)。历史过程见 [1.1.0 → 1.9.0](09-driver-upgrade-1.9.0.md)及 [1.9.0 → 1.10.0](10-driver-upgrade-1.10.0.md)，本轮见 [1.13.0 验证及只回退驱动](11-driver-upgrade-1.13.0.md)。每轮结果独立记录；下一版先阅读[升级流程](12-driver-upgrade-runbook.md)，不套用旧硬编码结论。
