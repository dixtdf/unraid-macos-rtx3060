# macOS 26 升级准备：保留 15.8.1，在隔离克隆中试升

记录日期：2026-10-19。本轮目标是准备升级环境；**尚未安装 macOS 26，试验克隆也尚未启动**。生产 VM 继续运行 macOS 15.8.1 / 24H32、OpenCore 1.0.5 和 NullMoth 2.3.7 + 实验性 RTX 3060 NVENC 补丁。脱敏状态见[本轮结果](../results/observed-2026-10-19-tahoe26-preparation.json)。

此前 [1.9.0 回退](11-driver-upgrade-1.13.0.md)属于 10 月 11 日历史。当前驱动的固定资产、安装过程和完整验收在 [2.3.7 更新记录](https://github.com/dixtdf/nvidia-macos-driver-3060-nvenc/blob/main/docs/upgrade-2026-10-19-v2.3.7.md)。预热后的 3600 帧资格测试为 60.003 FPS、编码 p95 2.776 ms、零错误 / 丢帧，GlideBeam 30 帧生产像素自测通过；首次 55.33 FPS 未达资格门槛的结果也保留。这些是 macOS 15 上的编码探针证据，不能写成远控端到端稳定 60 FPS，更不能当作 macOS 26 已通过。

## 本轮准备状态

| 项目 | 已完成 | 边界 |
| --- | --- | --- |
| 当前系统恢复点 | 正常关机后冷备系统盘、EFI、旧 Delivery 盘、UEFI NVRAM 与 VM XML；qcow2 检查通过 | 同一磁盘上的独立 reflink 副本可隔离写入，不能抵御物理磁盘故障 |
| 试验 VM | 独立磁盘和 NVRAM，已定义，关闭自动启动 | 尚未启动；与生产 VM 共用同一张直通 GPU，保留相同 Apple 身份和网卡 MAC，必须互斥运行 |
| 试验系统盘 | 虚拟容量从 160 GiB 增至 240 GiB | 客户机 APFS 仍为原容量；仅在未来确认是克隆磁盘后扩容 |
| 试验 EFI | OC 1.0.5、Lilu 1.7.1、WhateverGreen 1.7.0，加入 RestrictEvents 1.1.6；ocvalidate 通过 | 配置校验不是开机验收；没有改写生产 EFI |
| 备用 EFI | 匹配组件的 OC 1.0.8 树和同版本 ocvalidate 校验已准备 | 尚未启用，不与系统升级同时默认切换 |
| 恢复工具 | root 拥有的官方 2.3.7 包、精确 NVENC 覆盖工具 / 探针和独立 Python 3.9；SHA256 校验通过 | 已随冷备进入克隆；没有自动执行安装或开机修复任务 |
| macOS 26 介质 | Apple 目录列出 26.7.1 / 25G241；完整包 Apple 签名通过，宿主与客户机完整 SHA256 一致；24 GiB 只读交付盘已就绪 | 不是可启动安装 U 盘，尚未安装安装应用 |
| 远程救援 | 克隆准备虚拟 VGA、仅监听回环地址的 QEMU VNC 和既有 SSH | 尚未从克隆实测登录、桌面或首次 26 启动；端口配置不等于画面通过 |

备份、EFI、XML、VNC 凭据及真实身份只保存在本地私有目录；公开记录不包含可直接启动的完整机器配置。恢复旧 EFI 不会恢复已经升级的系统盘，完整回退应使用本轮配套冷备或恢复未改动的生产 VM。

## 先处理机型检查与 Apple ID 修补的相互作用

当前 `iMacPro1,1` 不在 [Apple 的 Tahoe 支持机型](https://support.apple.com/en-us/122867)中。本轮保留现有序列号、MLB、ROM、SystemUUID 和机型，避免为了让安装器出现而随机改身份。绕过兼容检查只属于试验路径，不构成官方支持。

[OpenCore 1.0.5](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.5)已修复 macOS 26 kext 注入兼容性；[Lilu 1.7.1](https://github.com/acidanthera/Lilu/releases/tag/1.7.1)也已允许 macOS 26。因此首轮克隆继续使用已工作的 OC 1.0.5；另备 1.0.8，不把更换引导器当作已证实的升级前提。

克隆加入 [RestrictEvents 1.1.6](https://github.com/acidanthera/RestrictEvents/releases/tag/1.1.6)，限定 Darwin `24.0.0–25.99.99`，在 Lilu 后加载，并追加：

```text
revpatch=sbvmm revblock=none revcpu=0 -no_compat_check
```

`-no_compat_check` 只覆盖引导层检查。`sbvmm` 对安装应用及已启动的 installer / recovery 的支持见 [RestrictEvents 1.1.3 发布说明](https://github.com/acidanthera/RestrictEvents/releases/tag/1.1.3)。本机实际安装器是否接受该配置，仍需在克隆中验证。没有添加 CPU 名称伪装、清除 CPU VMM 位、清 NVRAM 或重置 Apple 账户。

**克隆先成对关闭第 13 章的两项 Darwin 24 Apple ID 字符串修补，再允许 RestrictEvents 在 24 上加载。**原修补交换 `kern.hv_vmm_present` 与 `kern.hibernatecount` 的名称；[RestrictEvents 1.1.6 源码](https://github.com/acidanthera/RestrictEvents/blob/1.1.6/RestrictEvents/SoftwareUpdate.cpp#L146-L203)按前者名称查找并替换处理函数。结合 XNU 的[专用 VMM 处理函数](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/bsd/kern/hvg_sysctl.c#L175-L180)、[hibernatecount 注册](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/iokit/Kernel/IOHibernateIO.cpp#L1550-L1552)与 [`SYSCTL_UINT` 定义](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/bsd/sys/sysctl.h#L486-L490)，可推断两者同时启用会使 RestrictEvents 命中通用整数 sysctl handler，可能影响安装进程的其他查询。这是源码审查发现的风险，没有在生产 VM 上刻意复现。

生产 EFI 保持不变。克隆关闭旧修补后，Apple 服务行为可能变化；保留账户数据，不退出账户或清钥匙串。**不能把原修补的 MaxKernel 扩至 Darwin 25**；旧系统设置登录成功仅证明此前 15.8.1 的那次验证。

## 固定官方安装包

本次通过 Apple `softwareupdate --list-full-installers` 确认目标版本，再取其官方 CDN 的完整包。下载命令的 fetch 过程只取得安装资料，未运行系统升级安装器。

| 字段 | 固定值 |
| --- | --- |
| 目标版本 / build | macOS Tahoe 26.7.1 / 25G241 |
| Apple 产品编号 | `142-28081` |
| 完整包大小 | `18,380,974,544` 字节 |
| 已下载包 SHA256 | `ca854f49dfdedbe78492c26d0e4172ee4d37573e2d375ca90c083d7615b6f48a` |
| 来源 | [Apple CDN InstallAssistant.pkg](https://swcdn.apple.com/content/downloads/51/17/142-28081-A_616Q67X32N/5atqz1miz61kmrim7fwkn7yi62xuzzcc0s/InstallAssistant.pkg) |

SHA 是本轮下载后的摘要，不能代替 Apple 签名。24 GiB exFAT 交付盘已向客户机只读挂载，`pkgutil --check-signature` 通过，显示由 Apple Software 签名，证书链为 Software Update → Apple Software Update Certification Authority → Apple Root CA；客户机再次读取完整包得到相同 SHA256，临时介质已从生产 VM 移除，生产持久 XML 未变。试验 VM 的两个显示配置已加入该只读介质。

包元数据标识为 `com.apple.pkg.InstallAssistant.macOSTahoe`，包版本 `25.6.241`、应用 bundle 版本 `21.7.02`。这些是包 / 安装应用自己的版本，不能当作目标 macOS 的版本；26.7.1 / 25G241 来自对应 Apple 软件更新目录记录。介质保存完整 pkg，尚未安装 `Install macOS Tahoe.app`，也没有运行 `createinstallmedia` 或 `startosinstall`。旧 Delivery 盘空间不足，保留原内容，没有覆盖原盘。

## 实际试升时的顺序

以下为后续执行步骤，**本轮没有运行这些系统升级步骤**。每一步达到退出条件后再进入下一步。

1. 正常关闭生产 VM，确认 QEMU 退出、GPU 两功能为闲置 VFIO、BAR1 与 MMIO 满足原已验证配置。启动前核对克隆磁盘、独立 NVRAM、禁用自动启动及身份互斥规则，不能只依赖针对旧 VM 名称的宿主 hook。
2. 先让克隆启动原有 15.8.1，确认实际 EFI、RestrictEvents、SSH / VNC、系统盘归属与安装器兼容检查。若需扩 APFS，只对核对过克隆磁盘序列的盘操作。生产 VM 保持关闭，不能让同 MAC / Apple 身份的两台机器并行上线。
3. 在克隆准备完整安装应用后，**先关闭克隆、离线切换到含 `-nvoff` 的首启 EFI，再启动原有 15 并确认该模式下虚拟显示 / VNC 和 SSH 可用，最后才启动升级安装器**。这样自动重启进入 26 前已经禁止 NullMoth，避免加载旧 OS 的 NVAccel；不能等升级自动重启后才在线改 EFI。需要区分安装器中间重启与首次新系统启动，不能提前把错误版本的加速驱动当作可用。
4. 首次进入 26 后，经 SSH 核对真实 `sw_vers`、Darwin 版本、包摘要和目标盘，在实际 26 上执行官方 2.3.7 安装器的 CHECK 预检及对应系统安装，使用新系统的内核集合构建 AuxKC。安装命令和参数先按固定包内脚本重新审查。
5. 成功安装 26 payload 后，离线修改克隆 EFI 移除 `-nvoff`，重启并确认基础 2.3.7 驱动真正加载，再运行 NVENC 覆盖工具的检查和应用，重启验收。覆盖工具的 loaded-NVRM 版本保护必须保留，不能在 `-nvoff` 阶段绕过。
6. 在克隆完成下表的全部验收，才考虑后续替换生产环境。失败时关闭克隆，恢复原 VM 的 GPU 归属并启动原生产盘，保留失败证据。

私有交接中另备启动、EFI 阶段切换和 26 驱动修复脚本。已验证生产 VM 运行时拒绝启动克隆、15 系统拒绝执行 26 修复，以及启动盘序列检查拒绝原生产盘；尚未取得这些守卫在试验盘上的正向启动证据。修复脚本在只读介质中交付，未来先由管理员复制到 root 拥有的恢复目录，再显式执行；没有注册开机自动修复服务。恢复生产的启动分支不依赖损坏克隆或安装媒体仍可读取。

### 跨系统版本的驱动限制

官方 2.3.7 包包含 macOS 15 与 macOS 26 两套 NVAccel；本轮核对的可执行文件 SHA256 分别为：

```text
os15 NVAccel: 95bb946ad298f228fa489aecab9cc0bc149f74981658566e99233c479193269c
os26 NVAccel: 881569a85c9a6c5af67a8c7bda6c1df72484419fafe3d35e93db47b133f615e5
```

安装器按**当前运行的 OS**选择 payload，并以当前内核集合构建 AuxKC。因此，在 15 上安装成功不能证明未来首次进入 26 会自动换好驱动；不能用 Darwin 24 的内核集合预造 Darwin 25 AuxKC。固定包审查与恢复要求见[上游故障排查资料](https://github.com/nullmoth/nvidia-macos-driver/blob/e2b0e547a18841b7d944850b03c9e605df76720b/docs/TROUBLESHOOTING.md)。

官方 installer 的备份 / lastgood 机制也不能作为跨 OS 完整回滚方案。完整冷备和未升级生产盘才是这轮隔离试验的恢复基础。`-nvoff` 的源码用途不等于本机首次 26 VNC 已验证，所以必须先验收克隆救援入口。

## macOS 26 的验收门槛

| 类别 | 必须取得的新证据 |
| --- | --- |
| 系统与启动 | 实际 26.7.1 / 25G241，普通桌面启动，准确 EFI 与 kext 版本 / 摘要 |
| 显示与 Metal | 3060 显示、Metal 枚举、复制 / 计算 / 渲染与可见画面 |
| H.264 NVENC | 精确编码器选择、硬件使用标志、解码像素正确；3600 帧节拍测试与 GlideBeam 生产自测 |
| 远控 | Mac 编码和 Windows 解码模式、实际收到并显示的帧与延迟；SSH / VNC 可救援 |
| 音频 | 输出设备、系统声音与 GlideBeam 音频；当前 BlackHole 2ch 的既有结果不能直接移用 |
| 电源与 GPU | 正常重启、关机使 QEMU 退出、再次开机 GPU 可用 |
| Apple 服务 | 用户自行重试系统设置登录；不收集密码 / 验证码，不扩大旧内核修补 |

本轮尚未验证任何 macOS 26 上的 NVENC、Metal、音频、Apple ID 或长时间稳定性。仅有硬编 API 成功、CI 构建成功或驱动带 os26 文件，都不满足这些门槛。若只能软件编码，则未达到本机升级目标。
