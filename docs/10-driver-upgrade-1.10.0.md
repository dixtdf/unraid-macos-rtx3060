# 10. NullMoth 1.9.0 → 1.10.0 升级与软件编码兼容验证

记录日期：2026-10-11。参考 VM 已安装 **NullMoth 1.10.0** 并正常重启，仍为 macOS 15.8.1 / 24H32、OpenCore 1.0.5、RTX 3060 12GB、10 核 / 20 线程、16GiB。Metal 三项和本章的小规模视频、OpenCL 测试通过。

**1.10.0 在 RTX 3060 上不再提供 NullMoth H.264 / HEVC 硬编码器。** 本次是在使用者接受这一变化后升级，并同时修改 GlideBeam 加入 Apple 软件 H.264 回退。已发布的 **GlideBeam 0.2.0 没有该回退**；仅升级驱动、继续使用原版客户端和 Mac 主机程序，会失去原有远程画面。

## 编码变化与适用条件

[上游 1.10.0 源码](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.10.0/plugin/NVMTLDevice.m)的 `nvmtl_video_is_blackwell` 用 `NVK GB` 判断 Blackwell，H.264 与 HEVC 编码器注册函数都会跳过非 Blackwell 显卡。H.264 解码为这些显卡改用 classic 布局的 `libnvdec_h264_t2d.dylib`。此次 RTX 3060 实测中，两种格式的 `RequireHardwareEncoder` 会话创建均返回 `-12908`，与源码行为一致。

[1.9.0 记录](09-driver-upgrade-1.9.0.md)中 H.264 硬编码的 30 帧像素通过，HEVC 硬编码虽然 API 成功，但输出像素错误。1.10.0 的结论是**硬编码器不可用**，不能把它写成“HEVC 硬编码已修复”，也不能将软件编码成功算作硬编码成功。

[v1.10.0 发布说明](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v1.10.0)还涉及 OpenCL、managed GPU memory、纹理可写属性、显示模式与鼠标旧帧修复。本章仅验证下述范围，不代表这些变化全部通过，也未运行上游所述的 Geekbench 八项负载。

需要原版 GlideBeam 0.2.0 的硬编路径时，可保留已验证的 1.9.0。选择 1.10.0 时，先准备独立 SSH / VNC 救援入口，部署并验证能够软件编码的远控程序；软件编码会使用 CPU，实际帧率和延迟需要在目标机器上测量。

## 先保存完整的 1.9.0 恢复点

按[上一章的冷备份清单](09-driver-upgrade-1.9.0.md#先建立可恢复的完整冷备份)，通过 macOS 正常关机，确认宿主机为 `shut off`、QEMU 已退出且磁盘无占用，再复制所有可写盘及 backing chain、EFI、NVRAM、XML、BAR 配置与钩子。不能遗漏仍挂载的 delivery 盘，不能给可写盘建立硬链接来充当备份。

本次升级前恢复点包含 3 块盘、NVRAM、XML、宿主机钩子 / 启动脚本及固件，**8 项 SHA256 清单完整复核通过，源及备份 qcow2 检查通过**。旧 1.1.0 与 1.9.0 恢复点、安装包均保留。另存原 GlideBeam 应用及配置，保存现有签名身份，避免更换签名身份导致屏幕录制或辅助功能授权失效。

保留原 VM UUID、网卡 MAC、SMBIOS 身份、OpenCore、CPU 配置和 `-vsmccomp` 电源修复；不要对已有 VM 重新运行配置初始化工具。

## 校验并安装官方 tar

本次使用官方 tar 的 `install.sh`，不走 1401 Mac 应用修改 OpenCore 的流程。[官方 tar.gz 资产](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.10.0/nullmoth-nvidia-1.10.0.tar.gz)大小为 **269301698 字节**，SHA256 为：

```text
47f9cd65201409d48952eb84d122c32e8a1867045d8d8f61e890ad559324ccb5
```

在 macOS 的私有工作目录中执行，任一步失败均先处理，不继续安装：

```bash
set -e
package=nullmoth-nvidia-1.10.0.tar.gz
curl -fL --retry 3 \
  https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.10.0/nullmoth-nvidia-1.10.0.tar.gz \
  -o "$package"
test "$(stat -f %z "$package")" -eq 269301698
printf '%s  %s\n' \
  47f9cd65201409d48952eb84d122c32e8a1867045d8d8f61e890ad559324ccb5 \
  "$package" | shasum -a 256 -c -
mkdir upgrade-1.10.0
tar -xzf "$package" -C upgrade-1.10.0
cd upgrade-1.10.0/pkgroot
test "$(grep -cE '^[[:xdigit:]]{64}[[:space:]]' SHA256SUMS)" -eq 54
shasum -a 256 -c SHA256SUMS
sudo ./install.sh
# 检查安装输出；有错误时不要执行下一条。
sudo shutdown -r now
```

本次资产摘要和包内 **54 项 manifest 全部通过**；官方安装器试建 AuxKC、保存旧组件和安装均成功，随后正常重启。安装 / 卸载脚本与 1.9.0 相同。保留安装器打印的备份位置和日志；tar 会替换相关驱动配置，自定义项应先保存、逐项核对，不能把旧配置整体覆盖回来。

重启后与 manifest 比较的 **43 项已安装 payload 摘要全部一致**，包括 kext 和用户态组件。实际加载四个 kext；EFI 磁盘、VM XML 保持字节一致，身份未重新生成。NVRAM 在启动过程中自然变化，完整恢复时仍使用同一冷备份中的版本。

下载受阻时优先走实际下载机器可达的代理。另一台机器的 `127.0.0.1` 不能直接作为 macOS 的代理地址。

## 重启后的原生测试

切回本教程仓库根目录运行已有系统、Metal 和视频测试：

```bash
bash scripts/macos/verify-system.sh
bash scripts/macos/run-native-tests.sh
```

继续按[上一章验收清单](09-driver-upgrade-1.9.0.md#重启后的验收)比较已安装组件与 manifest，核对实际加载的四个 kext、Metal 插件、BAR1、完整类名的 AppleSMC / VirtualSMC 计数，以及正常关机后 QEMU 是否退出。磁盘上的摘要一致不等于运行中的组件已更新；kext 的 `CFBundleVersion` 也不能代替包版本判定。

| 测试路径 | 本次结果 | 范围 |
| --- | --- | --- |
| Metal 缓冲区复制 / 计算 / 渲染像素 | 三项通过 | 小规模正确性测试 |
| H.264 硬编码创建 | 不可用，`-12908` | 请求 `RequireHardwareEncoder` |
| HEVC 硬编码创建 | 不可用，`-12908` | 请求 `RequireHardwareEncoder` |
| Apple H.264 软件编码 → NVIDIA 硬件解码 | 像素通过，硬解标记为真 | 1280×720、30 帧；Y MAE 0.0753055556，UV MAE 0.035875 |
| Apple HEVC 软件编码 → NVIDIA 硬件解码 | 像素通过，硬解标记为真 | 1280×720、30 帧；Y MAE 0.1442592593，UV MAE 0.0821805556 |
| 正常重启 / 远程入口 | 重启后 SSH 恢复，VNC 端口可达 | 端口可达与实际画面验收分开记录 |

视频测试退出 0 只表示产生报告，应检查每条路径的 API 状态、实际硬件标记、帧数及像素指标。本次结果不代表 4K、HDR、全部 profile 或长时间稳定性。

### OpenCL 小规模正确性探针

在仓库根目录编译 [opencl-acceptance.c](../tests/native/opencl-acceptance.c)：

```bash
mkdir -p local/native-tests
clang -std=c11 -O2 -Wall -Wextra -Wno-deprecated-declarations \
  tests/native/opencl-acceptance.c -framework OpenCL -o local/native-tests/opencl-acceptance
local/native-tests/opencl-acceptance
```

本次选中 RTX 3060 / NVK GA106，报告 OpenCL 1.2 / OpenCL C 1.2。1009 个非均匀浮点输入的向量计算和 17 组 × 64 个工作项的局部内存、barrier 整数归约均为 **0 处不匹配**。这两项检验索引与同步结果，不能推导完整 OpenCL 兼容性或性能。

## GlideBeam 软件 H.264 回退

本次修改见 [GlideBeam PR #1](https://github.com/dixtdf/GlideBeam/pull/1)，源码提交 `6a6210e`，位于 `codex/software-h264-fallback` 开发分支；**尚不属于已发布的 0.2.0 下载包**。使用时应核对实际构建来源和配套 Mac / Windows 程序，不能只根据应用显示的版本号判断是否包含此修改。

修改后的 Mac 端优先尝试硬件编码；硬编初始化失败时，显式选择 Apple 软件 H.264 编码器。软件路径目标为 1920×1080、30fps、8Mbps，保持可见高度，不套用 NVIDIA 硬编的高度处理。Windows 端仍可使用 GPU 解码，并根据 Mac 报告的实际编码模式显示状态。

配套 Windows 客户端的“解码与传输”面板分列 **Mac 视频编码**与 **Windows 视频解码**；本机路径显示“Apple 软件 H.264”与“GPU 硬件解码”。断线、采集暂停或旧主机没有上报时显示等待状态，不继承上次模式。这条屏幕传输链路由 Mac 编码、Windows 解码，不将 Mac 的原生硬件解码测试结果当作远控正在使用的解码模式。

已完成的验证：

- Mac 编码自测自动选中 Apple 软件 H.264，1920×1080、30 帧；Y MAE 为 0，UV MAE 为 0.01557108077，像素验收通过。
- 将同一编码路径产生的测试帧交给 Windows 生产解码器：提交 30 条帧记录，实际显示 29 帧，GPU 解码通过。不能将提交条数写成显示帧数。
- 生产路径曾因软件编码器缓冲首帧而没有输出；软件路径现在完成每帧提交，自测确认单帧回调及时完成。编码 session 独立管理待完成帧，故障模型验证旧回调不影响新会话、失败帧不会重复释放。
- 最终构建的真实 30 秒自有窗口动画测试实际显示 **795 帧**，1920×1080、Windows GPU 解码，预热后约 29fps；该轮首帧 1375ms、末次 RTT 2.843ms。首帧、网络 RTT 和端到端输入延迟是不同指标。较早的一轮动画出现长停顿，最终这一轮未再次出现；没有据此宣称长时间稳定。
- 重连后收到 110 条视频记录。专用输入窗口收到鼠标按下、滚轮、固定 Unicode 文字和成对按键，Shift 释放正常；局部监视器没有记录鼠标抬起，不把此项写成全鼠标事件通过。用户确认冷启动后可连接，尚未完成主观操作验收。

30fps 是配置目标，未据此宣称稳定达到 30fps。真实画面、输入、重连、吞吐与延迟应使用部署后的程序另行验证，保留 SSH / VNC 救援入口。

## 恢复点与回滚

正常重启后 SSH 恢复；正常关机使 QEMU 进入 `shut off`，随后建立 1.10.0 升级后完整冷备份，系统盘与备份为独立 inode，源盘和备份的 qcow2 检查均通过。完整 **8 文件 SHA256 再读取校验全部通过**，见[实测摘要](../results/observed-2026-10-11-1.10.0.json)。升级前及更早恢复点继续保留；冷备完成后机器已再次开机，登录启动的 GlideBeam 主机正常运行。

VNC 认证成功并收到两个 1920×1080 framebuffer 更新，但该轮读取的图像接近全黑，因此只记录认证和协议读取通过，不宣称 VNC 桌面内容已验收。GlideBeam 的实际视频显示由独立的 Windows 解码测试验证。

需要回到 1.9.0 时，正常停止 VM 并确认 QEMU、磁盘占用状态，校验后恢复**同一个完整冷备份**中的系统盘、EFI、NVRAM、XML、附加盘和相关钩子；原 GlideBeam 应用也应恢复到与该状态配套的版本。替换前另存当前失败状态，所有目标路径逐一核对。

`uninstall.sh` 移除驱动并重建内核集合，**不会自动恢复旧安装器备份**，不能用它代替回到 1.9.0 的完整恢复流程。继续保留旧恢复点，公开结果只放版本、摘要、测试范围和结论，不上传真实配置、完整日志、私有路径、身份或凭据。
