# 给 AI 的入口

这是 Unraid / QEMU 上安装 macOS 15.8.1、隔离试升 26.7.1，并为 RTX 3060 12GB 配置 NullMoth 驱动的复现仓库。先阅读资料再操作，不把文件名、PCI 识别或 API 成功当作完整验收。

## 阅读顺序

1. [README.md](README.md)：环境、版本、实测范围和章节入口。
2. [AI 教材](docs/AI-GUIDE.md)：执行阶段、决策规则、排障模型与交接格式。
3. [机器可读索引](ai/knowledge.json)与[实测摘要](results/observed-2026-10-09.json)。
4. 当前任务对应的教程章节，以及准备运行的脚本和配置模板。需要安装时，先生成身份配置再建立 EFI 和 VM。

**2026-10-23 后续核对：**官方从 2.4 起加入 RTX 20 / 30 的 H.264 / HEVC 硬编，最新正式版为 2.5.3；本机仍为已验收的 2.3.7 + 补丁，尚未升级官方新版。已清理被最终恢复点替代的两份升级前备份及安装介质，当次释放约 62.6 GiB；当前 26、原 15 和最终 26 冷备保留。见[更新与清理记录](docs/16-upstream-native-nvenc-and-cleanup.md)。

**最新记录（2026-10-19）：**隔离克隆已完成 **macOS Tahoe 26.7.1 / 25G241（Darwin 25.6.0）** 升级，保留 OpenCore 1.0.5，使用 **NullMoth 2.3.7 os26 + 实验性 RTX 3060 NVENC 补丁**。Metal 三项、H.264 3600 帧硬编像素资格通过（**60.004 FPS、编码 p95 3.502 ms**），重启后的 Metal / GlideBeam 30 帧硬编像素复验通过；**用户已确认光梭实际连接和控制正常**。首次设置完成，当前为纯显卡直通、EFI / 系统两盘、20 vCPU / 16 GiB，已移除 `-nvoff`、虚拟显示和安装介质。正常重启、关机及最终完整冷备通过，26 已重新开机；原 15.8.1 关闭保留，必须互斥。资格测试不等于端到端稳定 60 FPS；音频内容、26 上重新登录 Apple ID、HEVC 等未复验项目仍按实记录。先读[第 15 章](docs/15-macos26-upgrade.md)与[本轮结果](results/observed-2026-10-19-tahoe26-upgrade.json)。[第 14 章](docs/14-macos26-preparation.md)及其结果保留安装前快照；下文 1.9.0 属于 10 月 11 日历史。

资料里的“实测”属于参考机器：2026-10-09 的 1.1.0 初装，以及 2026-10-11 的各轮驱动验证。该历史轮 1.13.0 验收后仅回退驱动到 1.9.0，保留当时数据，完整冷备与冷启动已通过，见[历史记录](docs/11-driver-upgrade-1.13.0.md)、[1.13.0 结果](results/observed-2026-10-11-1.13.0.json)与[该轮最终回退结果](results/observed-2026-10-11-rollback-1.9.0.json)。分别读取对应 results 和章节，不能混用版本结论。现有机器实际状态通过只读检查确认。公开模板是参考，不是填好的可用 EFI。通用导出脚本没有在另一台服务器端到端重跑。

同日后续的 [Apple ID 排障](docs/13-apple-id-troubleshooting.md)与[脱敏结果](results/observed-2026-10-11-apple-id.json)单独记录。用户已确认系统设置登录成功；不外推到 App Store 独立登录、iMessage、FaceTime 或其他 VM。其后 EFI 含两项仅 Darwin 24 生效的字符串修补，旧驱动回退记录中的 EFI 未变结论仍只属于当时那轮。

## 必须保留的约束

- 初装基线为 macOS 15.8.1 / 24H32；当前升级克隆已为 26.7.1 / 25G241、OpenCore 1.0.5、2.3.7 os26 + 实验性 NVENC，已完成首次设置、用户光梭验收、电源复验和最终冷备；未测功能见第 15 章。1.9.0 是截至 1.13.0 的那轮审查中最后为 3060 注册 H.264 硬编的官方 release，并非所有后续版本 / 补丁的结论。每次按[通用流程](docs/12-driver-upgrade-runbook.md)审查固定资料、完整冷备并重新验收，不默认追最新版。
- 26 准备以互斥运行的独立克隆为边界；相同 Apple 身份 / NIC MAC 和同一张 GPU 不允许两台并行。只在克隆成对禁用旧 Darwin 24 Apple ID 字符串修补后启用 RestrictEvents sbvmm，不能扩大旧补丁到 Darwin 25。首次 26 启动保留 `-nvoff` 救援阶段，在实际 26 安装匹配 NVAccel / AuxKC，移除禁用参数、加载基础 NVRM 后才应用 NVENC 覆盖。准备、ocvalidate、包内含 os26 文件均不是 26 开机或功能验收。
- 2026-10-11 历史：[GlideBeam v0.2.1](https://github.com/dixtdf/GlideBeam/releases/tag/v0.2.1)正式发布，硬编优先、Apple 软件 H.264 回退和模式信息面板已合并，四架构 ZIP / SHA 清单已验证。此前没有正式 0.2.0 release；旧本地构建不一定含回退，当轮保留显示 0.2.0 的 `6a6210e` Mac 开发签名构建，已有回退、未替换签名或 TCC。这不是当前应用构建的证明；接手时核对提交、二进制和签名来源，不只看版本号，不得静默升级破坏远控路径。
- 已有 VM 保留其 UUID、MAC、ROM、SSN、MLB；不要再次 `init` 或用公开范例替换身份。新 VM 才用官方 macserial 生成配对并初始化。
- Apple ID 排障先核对实际 EFI、GUID NVRAM、内建 `en0`、UUID 派生、时间 / 网络与认证日志，不随机换身份或清除钥匙串。第 13 章属于 15.8.1 / Darwin 24 历史：两项 sysctl 字符串修补使 `hv_vmm_present` 读取休眠计数，须关闭休眠，且内置 AppleQEMUGuestAgent 因值不为 1 退出；当轮正常电源另行验证。升级克隆已成对禁用这两项修补、使用 RE `sbvmm`，实测 `hv_vmm_present=1`、QGA 可用；不改原 15，也不将旧补丁扩展到 Darwin 25。26 的 Apple ID 仍待用户确认。公开模板不默认加入修补，EFI-only 回滚不恢复旧 VDisk。
- `local/` 保存真实身份和 OSK。密码通过使用者授权的凭据机制取得，不写入发布文件、日志或命令示例。真实 EFI / XML / 镜像都不能直接发布。
- 安装后移除 Recovery / Installer / Delivery 盘，保留唯一 EFI 和系统盘。移除虚拟显示器前先验证客户机 VNC / SSH。
- BAR1 调整需要 VM 停止、两功能为 VFIO、无 group / cdev 占用、设备支持 8GiB、有足够 MMIO。不要硬解绑活跃显卡。钩子不能调用 libvirt。
- 保留 QEMU AppleSMC，使用 `-vsmccomp` 消除重复服务；预期 1 AppleSMC / 0 VirtualSMC IOService。不要用强行断电掩盖关机故障。
- CPU 实测是 10 核 / 20 线程，ES 名称未修复。部分 CPUID 显示 16/32 不代表更多算力。不要恢复失败的 RestrictEvents 伪装。
- 1.9.0 本轮回退后 HEVC 硬编 API 成功但像素严重失败，OpenCL 参数设置返回 -49 且两任务未运行，Apple 软件 H.264 → Mac 硬解有明显像素误差；不能宣称全功能或全部硬解正确。GlideBeam NVENC 30 帧生产自测与 Windows 实际 30 秒显示 1374 帧通过；1.13.0 不可用的硬编与此像素失败是不同状态。保留各版本失败和未测项，不照抄旧结论。
- 仅回退驱动保留当前用户数据时，审查安装器支持的 payload 接口；本轮用完整未改的 1.9.0 包配合官方 1.13.0 安装器 `--payload`，保留 ditto 备份和准确 VERSION marker。完整冷备用于故障救援，不直接恢复较旧 VDisk 丢弃新数据。包清单真实项数不同：1.9.0 为 53 项 / Library 42 项，1.13.0 为 54 项 / Library 43 项。

## 操作方式

先区分“输出方案”“审查配置”“实际安装 / 修复”。输出文档不需要连接或修改服务器。实际操作在用户授权范围内持续完成；已有授权不要重复询问。只在缺少必要信息或下一步会破坏授权范围外的现有数据时暂停，并说清楚具体原因。

先做只读盘点，再给关键修改建立完整冷备份，一次修改一个层次并验证。不能启动的机器优先恢复显示 / 远程入口及已知可用配置。不要把随机增加 boot-args、重建 KC、清 NVRAM、换 CPU 类型当作默认排障。

读取大日志时先筛选和压缩；有 Headroom 时用于超过 100 行或重复结构的输出，没有时分段读取并保留原始文件路径。摘要保留错误、版本、关键状态和未验证项，不保留凭据。下载失败时按用户配置使用代理；`127.0.0.1` 指运行下载命令的机器，不自动等于 Unraid 的代理。

修改仓库后运行 `python -m unittest discover -s tests -v`、`python tools/check_publication.py` 与 shell 语法检查。修改 OpenCore 后额外运行官方 ocvalidate 1.0.5。维护结论时区分参考实测、本机新实测、静态推断与未验证，保留来源和测试范围。
