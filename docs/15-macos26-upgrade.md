# macOS 26 克隆升级：完成记录

记录日期：2026-10-19。接续[第 14 章的准备快照](14-macos26-preparation.md)，**本轮实际升级完成：26.7.1 / 25G241 已正常运行，Metal、H.264 NVENC 像素资格与重启复验通过，用户确认光梭连接和控制正常；最终冷备完成后已重新开机。**固定官方 2.3.7 os26 驱动与实验性补丁的范围、中途失败和未复验功能均保留在本章及[脱敏结果](../results/observed-2026-10-19-tahoe26-upgrade.json)。

原 macOS 15.8.1 / 24H32 生产 VM 已正常关闭，保留原盘和原 EFI；升级在独立克隆上进行。原机和克隆保留同一 Apple 身份及网卡地址，并共用直通 GPU，始终互斥运行。当前固定驱动为 NullMoth 2.3.7 + 实验性 3060 NVENC，15 上的既有证据见[驱动更新记录](https://github.com/dixtdf/nvidia-macos-driver-3060-nvenc/blob/main/docs/upgrade-2026-10-19-v2.3.7.md)，不能代替本轮 26 验收。

## 已完成的执行顺序

| 阶段 | 实际结果 | 边界 |
| --- | --- | --- |
| 克隆原系统启动 | 15.8.1、RestrictEvents 1.1.6、SSH 可用；`kern.hv_vmm_present=1`，QEMU guest agent 可用 | 旧 Apple ID 字符串修补只在克隆中成对关闭；Apple ID 没有重新登录验收 |
| 安装前救援 EFI | 关闭克隆、离线加入 `-nvoff`，再次启动原 15 成功 | 在自动升级重启前完成，未等到新 OS 首启再修改 |
| 可见救援入口 | QEMU VNC 实际看见 1280×800 桌面；原生 VNC 认证并取到两帧 1280 分辨率登录画面 | 早先 GPU + 双显示模式下原生 VNC 曾黑屏，失败保留，不能混用显示模式结论 |
| 安装应用 | 官方完整包成功安装出 `/Applications/Install macOS Tahoe.app` | 安装应用和系统升级是两个不同动作 |
| 克隆容量 | 修复克隆系统盘分区图后，APFS 扩至 249,999,998,976 字节 | 只操作已核对身份的克隆盘，生产盘未扩容 |
| 跨版本前置驱动处理 | 归档旧 os15 NVAccel，验证归档完整性；重建不包含它的 15 AuxKC，重启验证 | 只完成 15 的安全过渡，不是在 15 上生成 Darwin 25 AuxKC |
| 第二个完整冷备 | 安装应用、扩容、安全 AuxKC 后再次正常关机，冷备系统盘、EFI、NVRAM、XML；qcow2 检查通过 | 独立 reflink 仍位于同一物理存储，不能当作抗磁盘故障的异地备份 |
| 运行实际系统安装器 | 07:23 UTC / 15:23 中国标准时间启动，虚拟机兼容检查被接受；15:58 准备进度到 100%，安装队列成功，15:58:35 开始应用 | 期间 33.3% 校验曾长时间不变，采样确认有 SHA1 / 读取活动，未按卡死中断 |
| 安装重启与迁移 | 16:00 前已重启进入安装 / 迁移阶段，画面显示 patchd 已封印新的 25G241 系统卷；16:07 经 guest agent 执行 `sw_vers` 得到 26.7.1 / 25G241 | 当前仍有 `-bsdmgroot`，进程与模板显示 Migrator / InstallerProgress；这是临时迁移根环境，不能写成正常桌面已启动 |
| 正常 26 系统根启动 | 16:11 经 SSH 核对 26.7.1 / 25G241、Darwin 25.6.0；启动参数无 `-bsdmgroot`，`loginwindow` / `WindowServer` 运行 | 后续确认仍有 Setup Assistant / MiniBuddy，控制台归 root，早期“用户已进入日常桌面”的判断不成立 |
| 官方 26 驱动修复 | 固定官方包 CHECK / 安装成功，os26 NVAccel 摘要匹配；新 lastgood 相关项经严格验证、备份和退出 / 归档后读回不存在 | 只处理本次新生成的对应项，保留备份；不是删除所有恢复资料 |
| 基础驱动与覆盖 | 正常关机后离线移除 `-nvoff`，四项 2.3.7 kext 加载、NVAccel 活跃；NVENC `--check` / `--apply` 成功，再重启进入纯 GPU 模式 | loaded-NVRM 保护没有绕过，补丁前基础文件已备份 |
| 原生验收 | Metal 复制 / 计算 / 渲染、30 帧硬编像素、3600 帧资格测试与 GlideBeam 30 帧硬编像素均通过 | 不代表用户远控端实际画面、输入、音频或 Setup Assistant 已通过 |

## `-nvoff` 不等于 kext 没有被加载

在首轮 `-nvoff` 验证中，IORegistry 四类活跃 NullMoth 服务计数均为零，但 `kmutil` 仍列出四个 kext。该参数在驱动服务启动路径提早返回，能够阻止服务接管设备，**不能据此认为旧 NVAccel 类不会被内核装载**。

官方 2.3.7 的 NVAccel 分为 os15 / os26 两套。旧版类引用和私有符号若进入新 OS 的加载路径，仍可能发生不兼容；这是升级前要排除的风险，本轮尚未以“先让 26 加载旧驱动”来制造故障。固定上游资料见[故障排查说明](https://github.com/nullmoth/nvidia-macos-driver/blob/e2b0e547a18841b7d944850b03c9e605df76720b/docs/TROUBLESHOOTING.md)。

因此，在克隆 15 上先完成以下实际操作：

1. 用 `ditto` 保存旧 os15 NVAccel，核对完整文件清单的 SHA256。原可执行文件摘要为 `95bb946ad298f228fa489aecab9cc0bc149f74981658566e99233c479193269c`。
2. 将旧 NVAccel 从当前扩展安装位置移出，重建只含三项共同驱动、没有旧 NVAccel 的 **Darwin 24 AuxKC**，保留 `-nvoff`。
3. 重启克隆，核对旧 NVAccel 在 `/Library/Extensions` 不存在且没有映射加载，确认救援入口仍可用。
4. 再建立本阶段冷备，之后才运行系统升级安装器。

第一次前置检查把“没有匹配类时的空 `ioreg` 输出”当成 plist 解析，检查脚本因此停止，没有进行修改。修正为空输出单独判定后再执行，旧 NVAccel 没有丢失。可借鉴之处是让检查失败时停在修改之前，不能因为解析失败就跳过目标和加载状态保护。

## APFS 扩容失败与真实容量验证

虚拟盘已扩为 240 GiB，客户机 APFS 起初仍约 160 GiB。执行：

```text
diskutil apfs resizeContainer <克隆 APFS 容器> 0
```

返回“完成”，但容量读回没有增加。继续指定最大空间和首次明确指定 `250000000000B`，均遇到 `-69519`。因此没有把首个成功退出码记为扩容通过。

核对克隆整盘、APFS 物理存储以及独立 OpenCore 引导盘的对应关系后，只对克隆系统盘执行：

```text
diskutil repairDisk <克隆系统整盘>
diskutil apfs resizeContainer <克隆 APFS 容器> 250000000000B
```

第一步按提示确认修复该系统盘的 EFI 分区 / 分区图。本机真正启动的 OpenCore EFI 位于另一块独立盘，这一关系已先核对。修复后重试成功，APFS 容量读回 **249,999,998,976 字节**，`df` 约 **233 GiB 总量、117 GiB 可用**。

这是本轮具体错误和隔离克隆条件下的处理，不是通用安装前必须执行的磁盘修复。验证应同时包含整盘归属、容器字节数和文件系统空间，避免把命令结束误记成操作目标已经达成。

## 系统安装器实际进度

在完成第二次冷备并重新启动克隆后，2026-10-19 **07:23 UTC / 15:23 中国标准时间（UTC+8）**运行：

```sh
"/Applications/Install macOS Tahoe.app/Contents/Resources/startosinstall" \
  --agreetolicense --forcequitapps --rebootdelay 30
```

安装器接受了该 VM 的兼容性检查。15:26:42 中国标准时间，日志显示 SharedSupport 已验证并解出更新 bundle；随后进度在 **33.3%** 校验阶段长时间不变。进程仍在运行，采样可见 SHA1 校验和读取活动，因此没有直接按卡死处理。15:58 准备进度达到 **100%**，安装队列报告成功，15:58:35 出现 `installerStartingApply`。

16:00 前客户机重启进入安装 / 迁移阶段。控制台画面显示 `patchd` 已封印新的 **25G241 SystemVolume**；16:07 通过 QEMU guest agent 的 `guest-exec` 执行 `sw_vers`，实际得到 **26.7.1 / 25G241**。这已经超过了仅从下载目录推断目标版本的证据。

但同一时刻启动参数仍含 **`-bsdmgroot`**，进程与模板显示 **Migrator / InstallerProgress**，根环境属于临时迁移系统。因此 16:07 的观察只记为“实际进入 26 迁移环境”，当时不记为正常桌面已启动。此阶段 SSH 尚未开放，QEMU guest agent 可用，没有因为临时环境无 SSH 就重装远程服务或驱动。

**16:11 中国标准时间取得了正常系统根启动的新证据：**经 SSH 执行 `sw_vers` 得到 **26.7.1 / 25G241**，Darwin **25.6.0**；`kern.bootargs` 保留 `-nvoff`，已经没有 `-bsdmgroot`。`loginwindow`、`WindowServer` 在运行。APFS `df` 为约 **233 GiB 总量 / 137 GiB 可用**。这组证据将状态从临时迁移环境推进到正常 26 系统根启动，原 15 生产 VM 继续关闭且未改动。后续发现 Setup Assistant / MiniBuddy 尚在、控制台归 root，因此修正早期“mac 用户已进入日常桌面”的判断；后台系统可访问不等于升级 GUI 已结束。

root 恢复工具核对当前启动盘属于克隆后通过保护检查，16:11 开始执行固定官方 2.3.7 包的 26 CHECK / 安装修复流程；后续取得 CHECK 和安装成功结果，os26 NVAccel 可执行文件摘要为 `881569a85c9a6c5af67a8c7bda6c1df72484419fafe3d35e93db47b133f615e5`，匹配固定包。

## 试验 VM 名称与宿主 BAR hook

原 BAR hook 只匹配生产 VM 名称。为使试验 VM 也走现有资源准备逻辑，先备份原始 hook，再仅加入试验名称匹配，保留原 BDF、空闲 VFIO / 占用检查等保护。更新已持久保存在现有 `libvirt.img`，没有在此次编辑时操作正在活动的 GPU。

这是宿主启动路径的维护，不能写成已完成一次新的 BAR 调整或 GPU 功能验收。后续关机再启动仍需核对 hook 实际执行、BAR1 和设备归属。

## 26 驱动恢复与实测

官方 26 安装器生成的新 lastgood 项经 root 工具严格核对后归档，先保留备份，再仅对这一轮生成的启动项与 helper 执行退出 / 移出，并读回确认原位置已不存在。没有把旧 15 的 NVAccel / AuxKC 当作 26 的自动恢复来源，也没有泛化删除其他启动任务。

正常关机并离线移除 `-nvoff` 后，四项 2.3.7 kext 已加载，NVAccel 在 IORegistry 中实际活跃。之后 NVENC 覆盖工具 `--check` 通过 loaded-NVRM 版本保护，`--apply` 应用固定候选，保留覆盖前基础文件备份；候选资产 SHA256 为 `e6171560048fc8ebcdc061360ec79aa4d8100bb4f6d994946aaa11d2e3c90f4e`。再次重启进入不带虚拟 VGA 的 GPU 模式后执行验收。

首次 Metal 外层脚本将 JSON 中数字 `1` 形式的 `all_gpu_tests_pass` / `pass` 当作非布尔真，提前停止。但原始报告里复制、计算、渲染都为通过且错误数为零。保留这份报告，随后把外层判断修为只接受布尔 `true` 或整数 `1`，并同时要求各错误字段为零，再运行完整验收。这是报告类型兼容问题，不是 Metal 任务失败。

新的 `08:18 UTC` 验收记录：

| 测试 | 结果 | 范围 |
| --- | --- | --- |
| Metal | 复制、计算、渲染三项通过，零错误 | 原生小规模任务，不是所有应用或长期稳定性 |
| 30 帧 H.264 smoke | 硬件标志、解码像素通过；26.374 FPS，编码 p95 3.717 ms | 该 smoke 用于正确性，不设吞吐资格门槛；不能把此帧率与 3600 帧节拍测试混用 |
| 3600 帧 H.264 qualification | 3600 帧全部解码并验像素，60.004018745 FPS，59.995981524 秒，编码 p95 3.502125 ms；严格硬件验证通过 | 编码探针资格通过，不代表双端显示稳定 60 FPS |
| GlideBeam 生产像素 | 30 帧、精确 NVENC 编码器 ID、硬件模式与像素通过；自测后恢复原 host | 不包含 Windows 实际远控画面 / 输入验收 |

3600 帧资格报告 SHA256：`69e6e641ec9a712858f3f78be82010e999bbcc1d8c1a2a16eae32578ad99d54b`。首次外层判断停止的报告和后续通过记录分别保留，不能改写成同一次测试。

## GUI 收尾、USB 输入修复与最终冷启动

最初纯 GPU 模式下，macOS 26 的 Setup Assistant / MiniBuddy 尚未结束，控制台用户为 root；原生 VNC 认证成功，但取画面超时，系统截图 CLI 也未能生成图像。没有据此宣布桌面远控可用，也没有把“探针可用”当作整个系统已完成设置。

因此正常关闭克隆，离线切回 `-nvoff` 与虚拟 VGA；实际看到了 Setup Assistant 的 AutoUpdate 完成页。这是已验证驱动之后的显示 / 交互收尾，前述 Metal 和硬编通过结果保留。

### QEMU XHCI 的 HS 端口不枚举

当前 QEMU XHCI 的端口数设为 15，SuperSpeed 端口占用前段编号，HighSpeed 从 16 起；Mac 没有枚举到相应 HS 输入设备。把试验 VM 控制器的端口数改为 **4** 后，实际编号为 **SS 1–4、HS 5–8**，USB tablet 的 port 2 和键盘的 port 3 在 Mac 中得到实际识别。只更改克隆配置，原 15 保留。

通过 QMP 注入点击时，按下和抬起分为两次 report，界面实际向前推进；不能以一次命令返回成功代替界面状态变化。依次完成 AutoUpdate、FileVault 页面和 New Features：**FileVault 保持关闭并确认继续**，New Features 选择跳过，没有为了绕过页面直接伪造完成标记。

系统日志在 **16:45:17 中国标准时间**记录 `Completed prelogin tasks`；系统自行写入 `LastPreLoginTasksPerformedBuild=25G241`、`MiniBuddyShouldLaunchToResumeSetup=0`。旧 `LastSeenBuddyBuild` 仍为 `24H32`，保留实际值，没有为了看起来一致而改写。这是当时 prelogin 任务完成的新证据；最终纯 GPU 桌面和用户远控后来另行通过，见下文。

### 软件合成负载与引导参数的边界

临时虚拟显示阶段采样可见 `CompositorSW` 高 CPU。先备份偏好后，将 `reduceTransparency`、`reduceMotion` 设为 `true`；降低负载的效果未做独立对照验证，不把它写成已证明的性能修复。

另在新 EFI 副本中只追加官方 2.3.7 的通用前提参数 `ipc_control_port_options=0`，两套 EFI 阶段均经 ocvalidate 1.0.5 通过。它不是本轮已证实的 GUI / VNC 根因；此时没有加入 AMFIPass，也不据此扩大修改。

### 最终配置、桌面和用户验收

客户机正常关闭，宿主 QEMU 事件在 **08:47:21 UTC / 16:47:21 中国标准时间**记录 `reason=shutdown`。随后离线恢复纯 GPU 配置：移除 `-nvoff`、虚拟 video / QEMU VNC 和安装介质，严格核对只有 EFI / 系统两盘、20 vCPU、16 GiB、XHCI ports 4 与上述 HID 配置后冷启动。

随后确认控制台用户为 `mac`，Setup Assistant 不再运行；系统自行写入 `LastPreLoginTasksPerformedVersion=26.7.1`、`LastSeenCloudProductVersion=26.7.1`。旧 `LastSeenBuddyBuildVersion=24H32` 仍保留，不把单个旧字段当作设置未完成，也不手动改写它。

**用户已实际测试光梭，并确认连接和控制没有问题。**主机日志持续报告 H.264 硬件编码传送。原生 VNC 在首次设置期间虽认证并读回 1920×1080 尺寸，原始画面读取仍超时；本轮不将它标为 26 可用的备用远控。QEMU VNC 属于临时 VGA 救援阶段，已从最终配置移除。用户确认不等于另行测得客户端稳定 60 FPS、音频内容正确或端到端延迟。

### 电源复验与最终冷备

正常重启在宿主收到 **09:06:22.225 UTC** 的 libvirt `reboot` 事件；客户机启动时间实际更新为 **17:06:32 中国标准时间**，SSH / QGA 恢复。重启后再次通过 Metal 复制 / 计算 / 渲染与 GlideBeam 30 帧 NVENC 硬编、强制 IDR 和解码像素自测。

这轮摘要清单首次有一行手工复制漏位，`shasum` 给出格式警告；原生像素测试通过，但那次不能称为三文件摘要全部验证。改正为完整 64 位摘要，并启用 `shasum --strict` 后重跑，os26 NVAccel、NVMTL 覆盖和 H.264 编码库三项摘要及上述原生测试全部通过，保留两轮独立报告。

再正常关机，QEMU 在 **09:09:33.103 UTC** 记录 `reason=shutdown`，没有使用强制销毁。两台 VM 均关闭后，新建最终冷备，保存完整系统 qcow2、EFI、NVRAM、实际 XML、BAR 钩子、恢复控制脚本和私有验收索引；检查无 backing 文件、reflink 独立 inode、源配置前后未变、qcow2 无错误及小镜像 / 元数据 SHA256 读回。**没有声称对整个 qcow2 做 SHA256，也没有把同盘 reflink 当作抗物理磁盘故障的异地备份。**原 15 与安装前恢复点继续保留。

最终冷备完成后重新冷启动，客户机启动时间为 **17:10:53 中国标准时间**，SSH 再次确认 26.7.1 / 25G241。当前使用 26 克隆，原 15 关闭；相同身份和同一 GPU 始终互斥。

### 保留的范围与后续操作

| 项目 | 本轮结论 |
| --- | --- |
| 系统升级、Metal、H.264 NVENC、用户光梭连接控制 | 已通过；硬编码资格数字见上文，不外推客户端 FPS |
| 音频 | BlackHole 2ch 48 kHz 为默认输入 / 输出 / 系统输出；未另行复验实际声音内容、破音或延迟 |
| Apple ID / App Store / iMessage / FaceTime | 26 上未重新登录验证；保留原身份，15 的用户成功记录仍限于当时 |
| HEVC、OpenCL、OpenGL / Vulkan 等全功能 | 不从本轮 H.264 / Metal 小测试外推 |
| VNC 救援 | 26 原生取帧超时保留；临时 VGA / `-nvoff` 配置与 SSH / QGA 救援路径保留在私有备份 |

后续更新仍固定上游版本和补丁摘要，先冷备，再按真实 OS 选择 NVAccel / AuxKC，并保留 loaded-NVRM 保护和像素验证。回退入口是正常关闭 26 克隆后启动未改动的原 15 VM；26 期间的新数据留在克隆，不能把“切回原机”写成新数据已迁回，也不能仅用旧 EFI 覆盖已经升级的系统盘。

## 2026-10-23 后续清理

本章保留 10 月 19 日历史快照。两份升级前检查点和安装介质随后已按用户要求删除，最终 26 完整冷备、当前系统及原 15 VM 保留；恢复前须重新核对库存。官方 NVENC 更新结论和清理依据见[第 16 章](16-upstream-native-nvenc-and-cleanup.md)。
