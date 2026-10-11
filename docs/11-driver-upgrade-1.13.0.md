# 11. NullMoth 1.13.0 验证与回退 1.9.0 H.264 硬编

记录日期：2026-10-11。本章记录既有 macOS VM 升级到 [NullMoth v1.13.0](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v1.13.0) 的过程，升级前为 [1.10.0](10-driver-upgrade-1.10.0.md)。后续更新统一按[通用升级流程](12-driver-upgrade-runbook.md)执行，再为每次更新保存独立结果。

**最终驱动已仅替换为 1.9.0，完整冷备、再次冷启动和 GlideBeam NVENC H.264 路径均已验证。** 此前 1.13.0 完成了独立安装与软件传输验收，其证据保留在本章前半部分。[GlideBeam v0.2.1](https://github.com/dixtdf/GlideBeam/releases/tag/v0.2.1)已正式发布；本机仍保留原开发签名的 Mac 主机，没有换装正式包或重新申请授权。局部通过不等于全功能通过。

## 范围和升级前状态

本轮核对环境仍为 macOS 15.8.1 / 24H32、OpenCore 1.0.5、RTX 3060 12GB、10 核 / 20 线程、16GiB、BAR1 8GiB。已有 VM 的 UUID、网卡 MAC、SMBIOS、CPU、EFI、电源修复及远控授权保持原配置。

1.10.0 在本机不注册 H.264 / HEVC 硬编码器；此前验证的是 Apple 软件编码、NVIDIA 硬解码及 GlideBeam 软件 H.264 → Windows GPU 解码。1.13.0 源码仍只给 Blackwell 注册两个硬编码器；本轮 RTX 3060 的强制硬编创建均为 `-12908`，GlideBeam 实际使用 Apple 软件 H.264，Windows 继续 GPU 解码。

## 上游资料和固定安装资产

本轮已读取 v1.13.0 的发布说明、对应 tag 源码及包内 `install.sh` / `uninstall.sh`，并与 [v1.10.0 → v1.13.0 累计源码变化](https://github.com/nullmoth/nvidia-macos-driver/compare/v1.10.0...v1.13.0)比较。tag 对应提交为 `0960b2ef5dbc4a573056d4c8e042a5bd2e15d651`。

[1.13.0 说明](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.13.0/docs/RELEASE-1.13.0.md)重点为 Turing 初始化 settle、boot picker 卸载处理以及报告旧崩溃时间。本机 RTX 3060 属于 Ampere，不是 Turing；本次不增加面向 Turing 的 `nvrmsettle=10000`。

本轮相关累计变化如下，属于上游源码 / 包审查结果，不等于本机对应应用已测试：

- [NVK 的 `/dev/null` 占位 fd 改为只读](https://github.com/nullmoth/nvidia-macos-driver/commit/e4d8ca8e32)，用于浏览器 GPU sandbox 访问。
- [Metal viewport depth 范围和 NaN 默认值处理](https://github.com/nullmoth/nvidia-macos-driver/commit/3a5abdba49)，用于避免 Live Text / `mediaanalysisd` 的 NVK assertion。
- [1.12.0 增加 headless 处理](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.13.0/docs/RELEASE-1.12.0.md)，没有 NVIDIA 显示器时延后启动；本机仍接物理显示器，不能把它作为本机默认路径。
- [1.13.0 的视频注册源码](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.13.0/plugin/NVMTLDevice.m)继续用 `NVK GB` 判断 Blackwell；非 Blackwell 的 H.264 / HEVC 硬编注册被跳过，H.264 解码仍选择 classic 布局的 `libnvdec_h264_t2d.dylib`。

| 项目 | 本轮证据 |
| --- | --- |
| 固定 release | `v1.13.0`；不使用 `latest` |
| 实际选择的安装资产 | 官方 [nullmoth-nvidia-1.13.0.tar.gz](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.13.0/nullmoth-nvidia-1.13.0.tar.gz) |
| 文件大小 | 269301262 字节 |
| SHA256 | `994970b1bba53e3ae8d7f500ef27b25cae8bc6818abc112d35230a58e6882fdf`；与官方 digest 一致 |
| 包内 manifest 项数及完整校验 | Windows 与 macOS 均通过 54 / 54 项，0 失败 |
| 安装脚本审查、相对旧版本的修改 | 已审查；包内脚本与 tag 源码相同 |
| 安装器退出码及保存旧组件结果 | 退出 0，AuxKC 预检、四 kext、ditto 备份与安装完成 |
| 重启后已安装 payload 与 manifest 对比 | 本机 43 / 43 项 Library payload 摘要一致 |
| 已加载组件与实际版本证据 | 四 kext 已加载；`driver-version` 为 1.13.0，与已校验 payload 一致 |

如果 release 提供资产摘要，先与它比较，再记录本地摘要。包内 manifest 校验只能说明包内文件符合该清单，不能代替固定资产版本核对。下载受阻时使用实际下载机器可达的代理；另一台机器的 loopback 不等于本机代理。

[本版 tar 安装器](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.13.0/package/install.sh)不改 EFI、SIP 或 boot-args，不自动重启；它在内核集合成功发布后写入 `/Library/NullMoth/driver-version`。组件备份从 `cp -Rp` 改为 `ditto`，用于保存 Vulkan 符号链接。它会清除已有的 `nullmoth-remove` 标志；这与清空整套 NVRAM 或重新生成身份不同。预检模式 `sudo env CHECK=1 /bin/bash ./install.sh` 仅试建临时 AuxKC，不写入运行驱动。

实际 tar 仅包含 `NVRM`、`NVAccel`、`NVRMFB`、`NVRMAGDC` 四个 kext；源码中的实验性 `NMHDA` / `NMIntelFB` 没有打入此包。本次不将它记录为 HDMI / DP 音频或 Intel framebuffer 已修复。Mac 安装应用的额外 EFI 设置与此 tar 路径不同；例如 [1.11.0 提到的 `ipc_control_port_options=0`](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.13.0/docs/RELEASE-1.11.0.md)不是此安装器添加的参数，本轮不据此改动已经验证的 EFI。

复核本轮固定资产可使用以下命令；包内脚本应先审查，再执行安装：

```bash
set -euo pipefail
package=nullmoth-nvidia-1.13.0.tar.gz
curl -fL --retry 3 \
  https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.13.0/nullmoth-nvidia-1.13.0.tar.gz \
  -o "$package"
test "$(wc -c < "$package" | tr -d '[:space:]')" = 269301262
printf '%s  %s\n' \
  994970b1bba53e3ae8d7f500ef27b25cae8bc6818abc112d35230a58e6882fdf \
  "$package" | shasum -a 256 -c -
# 先审查 tar 文件清单和解压路径，再在新的私有目录解压与校验 manifest。
```

## 升级前完整冷备份

通过客户机正常关机，等待 Unraid / libvirt 为 `shut off`、QEMU 退出、磁盘无占用。记录所有附加可写盘及 qcow2 backing chain，备份系统盘、EFI、附加盘、每台 VM 的 NVRAM、XML、对应固件、BAR 配置和宿主机钩子 / 启动脚本。另存 GlideBeam Mac 应用、配置与现有签名身份。

先检查源 qcow2，再复制到新的独立恢复点；源和备份不能共用硬链接。检查 backing chain 的备份路径、备份 qcow2、完整 SHA256 清单并再次读取校验。真实路径、XML、身份、日志和截图只保留在私有目录；公开记录仅保存数量、范围和结果。

| 项目 | 本轮结果 |
| --- | --- |
| 升级前完整冷备份 | 48GiB 独立恢复点，系统 / EFI / 附加盘、NVRAM、XML、宿主机钩子 / 启动脚本及固件齐全 |
| 源 / 备份 qcow2 与 backing chain | 源和备份 qcow2 检查通过，复制内容与源一致 |
| 完整 SHA256 再读取校验 | 全部 8 项通过 |
| 更早恢复点保留 | 已保留，不以本次恢复点覆盖 |
| 原 GlideBeam 应用 / 签名身份 | 既有私有应用备份保留；本轮二进制不变、现有签名仍有效 |

本轮曾遇到 XML 输出末尾空行在 shell 变量捕获时被去掉，导致字节摘要比较不同；改为保存 `virsh` 原始输出后完成完整 8 项复核。这是输出捕获差异，未发现磁盘数据错误。后续记录文件摘要时保留原始字节，不根据终端显示结果重新拼接文件。

## 安装和正常重启

本轮在冷备完成、固定资产与 manifest 校验通过、脚本审查后使用官方 tar 安装器。试建内核集合、保存旧组件、安装均成功，退出码为 0，再从客户机正常重启。安装器备份位置、完整输出和日志保存在私有交接中。

重启后 SSH 恢复，桌面登录启动的 GlideBeam 主机进程恢复；已安装 43 项 payload 与包一致。EFI、XML、boot-args、GlideBeam 二进制、签名身份、宿主机 BAR 钩子及启动脚本均未改动，GPU 为 VFIO、BAR1 8GiB。实际服务为 1 个 AppleSMC / 0 个 VirtualSMC。NVRAM 随启动自然变化，不将它记为身份重新生成。

本轮安装与正常重启结论：**通过**。随后正常关机也使 QEMU 进入 `shut off`；没有通过强行断电完成本轮电源验收。

## 分别验证图形、编解码和远控

按[通用流程的验收矩阵](12-driver-upgrade-runbook.md#5-重启后逐层验收)运行本仓库原生测试。每条视频路径记录 API 状态、实际硬件标志、编码 / 解码帧数和像素误差；不能只看 `Metal 3`、编码器名单、API 成功或程序退出码。

| 项目 | 本轮结果 | 需要保留的范围 |
| --- | --- | --- |
| Metal 复制 / 运行时计算 / 渲染像素 | 三项通过 | 4096 字节、256 元素、64×64 像素，0 错误 |
| OpenCL 向量 / 局部内存与 barrier | 两项通过 | 1009 元素数组、17 组 × 64 工作项归约，0 不匹配 |
| H.264 硬编码 | 不可用 | 强制硬编会话创建 `-12908`，没有生成编码帧 |
| HEVC 硬编码 | 不可用 | 强制硬编会话创建 `-12908`，没有生成编码帧 |
| 软件 H.264 → NVIDIA 硬解码 | 像素通过 | 1280×720、30 帧、硬解标记为真；Y MAE 0.0753055556，UV MAE 0.035875 |
| 软件 HEVC → NVIDIA 硬解码 | 像素通过 | 1280×720、30 帧、硬解标记为真；Y MAE 0.1442592593，UV MAE 0.0821805556 |
| GlideBeam 实际编码模式 | Apple 软件 H.264 | 真实 QUIC `host-status` 报告 `apple-software` 与 Apple H.264 编码器 ID |
| GlideBeam 实际持续视频 | 通过 | 30 秒实际显示 819 帧，1920×1080、Windows GPU 解码 |
| GlideBeam 重连 / 输入 | 重连可传输；本轮未测输入 | 静止窗口 8 秒收到 2 条视频记录，无输入注入 |
| VNC 桌面内容 | 未验证 | 5900 监听及连通可达，不将它当作可见桌面证据 |
| 正常重启 | 通过 | SSH 和登录启动的主机程序恢复 |
| 正常关机 | 通过 | 客户机正常关机后 QEMU 进入 `shut off` |

GlideBeam 的 Mac 编码与 Windows 解码分列记录。生产编码器自测自动选中 Apple 软件 H.264，1920×1080 / 可见与编码高度均为 1080，30 帧、0 错误；强制 IDR、软件单帧及时完成和编码会话回调所有权检查均通过。解码后的 Y MAE 为 0，密集 UV MAE 为 0.01557108077，最大误差为 2，移动标记没有错位。

真实 30 秒传输使用自有动画窗口，819 是客户端实际显示帧数，含启动过程；采样末次 FPS 29.767、首个硬解帧 1282ms、网络 RTT 2.176ms。解码 / 转换提交 / DXGI Present 的 CPU wall 时间为 0.652ms，不能把它写成 GPU 耗时或端到端输入延迟。未据此宣称长时间稳定、固定 30fps、4K、HDR 或其他 GPU 通过。

本轮 1.13.0 验收使用含软件回退的 `6a6210e` Mac 开发构建，应用显示 0.2.0，原签名与 TCC 授权保留。Windows 验收使用与此软件回退配套的生产解码路径。[GlideBeam PR #1](https://github.com/dixtdf/GlideBeam/pull/1)已合并；正式版 0.2.1 源码提交为 `f6a00935e0f67f07ea0f3287d03f2c0a66f09642`，传输代码与本轮开发构建一致，发布版本元数据更新。

[唯一 v0.2.1 tag 发布构建](https://github.com/dixtdf/GlideBeam/actions/runs/38121558505)第 1 次运行通过，含 release job；Windows x64 / ARM64 与 Mac Intel / Apple Silicon 四个 ZIP、SHA256 清单共五项资产实际下载后摘要、ZIP CRC、架构和公开内容检查通过。[v0.2.1 已正式公开发布](https://github.com/dixtdf/GlideBeam/releases/tag/v0.2.1)，不是 draft 或 prerelease，五项资产匿名访问为 200、长度一致。发布工作流由 tag 触发，普通 main 推送显示跳过发布不构成失败；本轮没有额外重跑发布。

本轮核对 GitHub 记录，此前没有正式 0.2.0 release / tag。0.2.0 只是相关本地构建的应用版本字段，是否包含软件回退以提交和二进制为准；不能沿用历史章节里“已发布 0.2.0 下载包”的说法作为当前发布状态。

## 升级后恢复点和冷启动

1.13.0 验收后正常关机建立 **50GiB** 独立升级后冷备份，它也作为驱动降级前恢复点。源 / 备份 qcow2、复制内容与源字节、全部 **8 项 SHA256 再读取**均通过，复核完成时间为 2026-10-11 07:19:58 UTC。旧版本恢复点继续保留，不以升级后备份替换升级前恢复点。

1.13.0 升级后完整冷备份：**通过**。随后启动原 VM 执行下面的仅驱动降级，没有恢复以前的整个系统盘。

恢复失败状态时，应在 VM 停止且无磁盘占用时，从同一个已校验恢复点恢复系统盘、EFI、NVRAM、XML、附加盘和配套宿主机配置，并使用匹配的远控应用。本版 `uninstall.sh` 即使接受并检查旧组件备份目录，也不会把其中组件重新装回；它移除现有驱动并重建干净 AuxKC。不能以卸载成功代替旧版本恢复。

## 用户选择仅回退驱动到 1.9.0

用户在 1.13.0 验证后选择恢复 RTX 3060 的 H.264 硬编。本轮查阅 1.9.0、1.10.0、1.11.0、1.12.0、1.13.0 的注册源码，1.9.0 是这些 release 中最后没有 Blackwell 限制的版本；1.10.0 起限制持续存在。本次仅替换驱动 payload，没有恢复以前的整个 1.9.0 系统盘，保留当前用户数据、EFI、GlideBeam、配对和授权。

使用官方 [1.9.0 资产](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.9.0/nullmoth-nvidia-1.9.0.tar.gz)，大小 **269295455 字节**，SHA256 为：

```text
573546d77d6999ef4f5a808b036da39fa99b4856909f02c7b95adef017a240f2
```

本轮 Windows 和 macOS 均与官方 digest 匹配，1.9.0 包内 **53 项 manifest** 通过；适用于本机的 Library payload 为 **42 项**。它没有 1.10.0 起新增的 classic H.264 解码库，因此不能沿用新包的 54 / 43 数量。

采用已经审查的 [1.13.0 安装器](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.13.0/package/install.sh)原有 `--payload` 接口，指向未改动的完整 1.9.0 `pkgroot`。安装器与 1.9.0 的四 kext / KC 替换流程相同，新版 `ditto` 备份保留现有 Vulkan 符号链接，并根据传入 payload 的 `VERSION` 写入正确的 `driver-version=1.9.0`。这可以避免旧安装器的 `cp -Rp` 符号链接问题以及留下误导性 1.13.0 marker。

在本轮私有工作目录中，核对两个目录和原始包的完整校验后按顺序执行；下列路径是占位范例，不是现场真实位置：

```bash
sudo env CHECK=1 /bin/bash /path/to/v113/pkgroot/install.sh \
  --payload /path/to/v190/pkgroot
# 预检失败时先处理，不继续安装。
sudo /bin/bash /path/to/v113/pkgroot/install.sh \
  --payload /path/to/v190/pkgroot
# 安装成功后再正常重启；核对 VERSION、42 项 payload、加载组件与全部验收结果。
```

本轮 CHECK 预检与实际安装均通过，安装器正常备份原 1.13.0 组件，版本 marker 写为 **1.9.0**；1.13.0 额外的 `libnvdec_h264_t2d.dylib` 已移除。客户机正常重启后 SSH 与登录启动的 GlideBeam 主机自动恢复。再次核对 EFI / XML、boot-args、身份、应用二进制 / 签名、BAR 钩子与启动脚本，均未修改。

### 1.9.0 新一轮图形和视频验收

| 项目 | 本轮回退后结果 | 范围或失败 |
| --- | --- | --- |
| 安装组件 | 42 / 42 项 Library payload 与官方包一致 | 包内 manifest 53 项，四 kext，版本 marker 准确 |
| 系统 / SMC | 配置保持不变 | 10 核 / 20 线程、16GiB、1 AppleSMC / 0 VirtualSMC |
| Metal | 复制、计算、渲染三项通过 | 4096 字节、256 元素、64×64 像素 |
| OpenCL | **失败，内核未执行** | `clSetKernelArg(vector_kernel, 0, ...) = -49`，向量及归约任务均未运行 |
| 原生 H.264 硬编 → NVIDIA 硬解 | 指定小样本通过 | 1280×720、30 帧；Y MAE 1.0855，UV MAE 1.842254630 |
| 原生 Apple H.264 软件编码 → NVIDIA 硬解 | 有明显像素误差 | Y MAE 11.37726852、UV MAE 5.450666667；仅勉强在旧测试 `<12` 阈值内，不能宣称普遍正确 |
| HEVC 硬编 | **API 成功、像素严重失败** | NVIDIA 硬解 Y MAE 125.5148148、UV MAE 127.7077778；Apple 软件解码同样失败 |
| Apple HEVC 软件编码 → NVIDIA 硬解 | 指定样本通过 | 30 帧；Y MAE 0.1442592593，UV MAE 0.0821805556 |
| 正常关机 | 通过 | 验收后正常关机使 QEMU 进入 `shut off` |

此次 OpenCL 的设备枚举虽然成功，两个测试都没有执行，报告中 0 mismatch 不是正确性通过。相较 1.13.0，本轮选择保留 H.264 硬编，接受 OpenCL 探针失败以及旧 H.264 解码布局的兼容性问题；没有更改阈值使报告变成通过。

编码器列表在初始枚举时只显示 Apple 编码器，但实际 `RequireHardwareEncoder` 会话成功，硬件标志为真，编码器 ID 为 `com.nvmtl.videoencoder.avc.nvenc`。因此列表、属性探测、实际会话和输出像素是四种独立证据。

### GlideBeam NVENC 生产路径

Mac 主机自动选择 **hardware / NVENC H.264**。生产自测使用可见 1920×1080、编码高度 1088 的 NVIDIA 布局处理，30 帧、0 编码错误；Apple 软件解码的 Y MAE 为 0，密集 UV MAE 为 0.00004234148407，最大误差 1。移动标记、强制 IDR 和编码会话回调所有权检查均通过。这条生产路径与上面的原生通用 VideoToolbox 测试分开记录。

Windows 真实动画验收 **30 秒实际显示 1374 帧**，GPU 解码；首个硬解帧 204ms、后段采样 FPS 56.514、RTT 1.628ms。解码 / 转换提交 / DXGI Present 的 CPU wall 时间为 0.528ms，不能把它当作 GPU 耗时或端到端输入延迟。总帧数包含启动和动画准备期，不据后段采样宣称整段稳定 60fps。此次没有重新注入输入或完成主观鼠标键盘验收。

### 最终恢复点与启动状态

1.9.0 正常关机使 QEMU 停止，建立约 **51GiB**（`du -sh`）的最终独立完整冷备。源 / 备份 qcow2 检查、与源文件字节比较及全部 **8 项 SHA256 再读取**通过，复核完成时间为 **2026-10-11 07:36:46 UTC**。1.13.0 前 / 后及更早版本恢复点全部继续保留。

随后正常冷启动，版本 marker 为 1.9.0，四 kext 已加载，SSH、GUI 桌面与登录启动的 Mac 主机程序恢复。再次核对 EFI、XML、boot-args、宿主机钩子 / 启动脚本、Mac 应用二进制与签名，均未改动；BAR1 仍为 8GiB。

最终真实 QUIC 连接持续 8 秒，收到 **27 条视频记录**；实际主机报告为 `hardware` / NVENC、可见 1920×1080、编码高度 1088、配置目标 60fps、编码错误计数 0，屏幕录制和辅助功能授权均为真。27 是接收记录数，不将它写成 Windows 实际显示帧数，也不根据配置目标宣称整段 60fps。这轮没有输入注入，VNC 可见桌面和用户主观操作仍未验收。

## 记录和后续更新

本轮独立保存 [1.13.0 实测](../results/observed-2026-10-11-1.13.0.json)和 [1.9.0 仅驱动回退实测](../results/observed-2026-10-11-rollback-1.9.0.json)，包含固定资产、安装、备份、逐项测试、失败 / 未测项以及 GlideBeam 构建来源。真实恢复点路径和安装器日志位置保存在私有交接文件中。README、AI 教材和索引指向本轮结果，同时仍保留 1.1.0、1.9.0、1.10.0 历史文件。

下一次更新按 [12. 通用驱动升级流程](12-driver-upgrade-runbook.md)重新核对现场、release、备份和功能变化；不要复制本章的旧摘要或通过结果给另一个版本。
