# 5. 远程访问、关机与重启

## 两种 VNC 的用途

Unraid 的 VNC 显示的是 QEMU 虚拟显卡，适合 OpenCore、Recovery、安装过程。NVIDIA 接管物理输出后，它可能黑屏。macOS 自带“屏幕共享”显示客户机桌面，最终通过它继续操作。

**必须在移除虚拟显示器前验证客户机 VNC 与 SSH。** 在 macOS 系统设置 → 通用 → 共享中开启“远程登录”和“屏幕共享”，指定允许登录的账户，并按客户端需要设置 VNC 兼容密码。不要公开这些密码。

在你的电脑测试 TCP 5900，并连接 `YOUR_MAC_IP`；UltraVNC 地址可以只填 IP（默认 5900），或 `YOUR_MAC_IP::5900`，关闭不匹配的 DSM 插件。macOS 本机检查：

```bash
sudo lsof -nP -iTCP:5900 -sTCP:LISTEN
sudo systemsetup -getremotelogin
```

不要在远端尚未连通时移除唯一可用的虚拟显示器。客户机重启时 VNC / SSH 会短暂离线；OpenCore 阶段不会由 macOS 屏幕共享提供画面。需要观察引导过程时，恢复 Cirrus / Unraid VNC 或依靠物理屏幕。

模板的安装阶段 QEMU VNC 仅监听 `127.0.0.1`。可从电脑建立 SSH 隧道到 Unraid，`virsh vncdisplay macos15` 返回例如 `:N` 时，实际端口为 `5900+N`：

```bash
ssh -L 15900:127.0.0.1:ACTUAL_VNC_PORT root@YOUR_UNRAID_HOST
```

客户端连接 `127.0.0.1::15900`。若使用 Unraid 网页 noVNC，按其现有认证代理配置监听；模板没有包含任何公网 VNC 密码。

## VNC 慢、RustDesk 无硬件编码

macOS 没有 Windows 那种内置 RDP 服务端；启用屏幕共享不会自动开放 RDP。第三方服务端需要另行安装和测试，本次没有将它作为完成条件。

VNC 可以先降低分辨率、显示缩放、颜色深度与客户端图像质量，并确保网络直连；它的传输路径不等同于 H.264 / HEVC 视频流。Metal 显卡正常也不能保证 VNC 流畅。

本次查看的 RustDesk 1.5.0 macOS 构建路径对 H.264 编码有禁用限制；HEVC 的 VideoToolbox 编码器属性字典查询又返回 `-12908`。原生 VideoToolbox H.264 能工作，并不说明 RustDesk 就会列出对应编码器。不要靠伪造支持标志强行启用；HEVC 硬编码的像素验收实际失败，不能用于可靠远控。

## 防止远程会话因为睡眠中断

专用、长期远程运行的 VM 可以选择关闭睡眠（有增加空闲耗电的代价）：

```bash
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 hibernatemode 0 powernap 0
pmset -g custom
```

按用途自行决定。macOS 的关闭显示器、睡眠、锁屏与系统关机是不同事件，不要把断开 VNC 当作 QEMU 已退出。

## 关机 / 重启没有到达 QEMU 的修复

这次问题的根因是 **QEMU `isa-applesmc` 与 VirtualSMC 同时提供 AppleSMC 服务**，IORegistry 出现两个 AppleSMC。系统已经卸载 APFS，但在 SMC 的关机 / 重启回调中递归并触发 page fault，QEMU 仍运行。仅修改 libvirt 的 `on_poweroff` 不能修复客户机内的回调问题。

VirtualSMC 源码明确处理这一冲突；`-vsmccomp` 使其使用已有 SMC。保留 XML 中 `isa-applesmc` 及使用者自己的 OSK，在两阶段 OpenCore 都加入 `-vsmccomp`。参考：[VirtualSMC 1.3.7 的兼容模式与重复服务注释](https://github.com/acidanthera/VirtualSMC/blob/1.3.7/VirtualSMC/kern_vsmc.cpp)。

重启后检查：

```bash
ioreg -r -c AppleSMC -d 0
ioreg -r -c VirtualSMC -d 0
```

预期 **1 个 AppleSMC、0 个 VirtualSMC IOService**。VirtualSMC kext 仍显示已加载可以正常，不应只凭加载列表判断冲突。

libvirt 中保留：

```xml
<on_poweroff>destroy</on_poweroff>
<on_reboot>restart</on_reboot>
<on_crash>restart</on_crash>
```

这里的 `on_poweroff=destroy` 表示处理客户机已完成的 poweroff 事件，并非执行 `virsh destroy` 强行断电。实测关机两次均正常退出 QEMU，热重启后 SSH 恢复。

先保存工作，再在 macOS 执行 `sudo shutdown -h now`，从宿主机验证 `virsh domstate macos15` 为 `shut off`；启动后再测 `sudo shutdown -r now`，确认网络恢复、显卡重新可用。宿主机 ACPI shutdown 和 Unraid 按钮可额外验证，但不能拿它们代替客户机发起的两项测试。不要用自动 hard poweroff 或看门狗掩盖尚未修好的系统关机。

后续 [Apple ID 排障](13-apple-id-troubleshooting.md)中的可选 sysctl 字符串修补会让 macOS 内置 `AppleQEMUGuestAgent` 退出，`guest-ping` 不可用；这项副作用已通过本机日志和只读反汇编确认。修补后另测正常热重启，宿主收到 `reboot` 事件；正常关机后为 `shut off`，日志为 `reason=shutdown`，没有用 watchdog 或强制断电替代。代理通道的状态与客户机正常电源路径分别记录，需要代理功能时评估 EFI-only 回滚。
