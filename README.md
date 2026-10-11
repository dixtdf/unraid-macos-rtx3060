# Unraid 上的 macOS 15.8.1 + RTX 3060 直通

> **远程桌面推荐：[GlideBeam / 光梭 v0.2.1](https://github.com/dixtdf/GlideBeam/releases/tag/v0.2.1)** 是我们新开发的 Windows 到 Mac 局域网远控软件，可临时替代延迟高、体验不佳的 VNC / RustDesk。它支持 H.264、剪贴板共享和文件传输，硬编优先、Apple 软件 H.264 回退，以及分别显示 Mac 编码 / Windows 解码模式。正式版提供 Windows x64 / ARM64、Mac Intel / Apple Silicon 四个包和 SHA256 清单，已校验下载、ZIP 与架构。本机仍保留同功能 `6a6210e` Mac 开发签名构建（显示 0.2.0），没有替换签名或重置授权。当前面向已登录的 Mac 桌面，保留 SSH / VNC 作为登录前操作和故障救援入口。

一份基于实际安装过程整理的中文教程：在 Unraid / QEMU 中安装 macOS Sequoia 15.8.1，再使用 [NullMoth NVIDIA 驱动](https://github.com/nullmoth/nvidia-macos-driver)驱动 RTX 3060 12GB，保留远程访问，并修复关机后 QEMU 不退出的问题。

2026-10-11 完成 **NullMoth 1.13.0** 独立验收后，按用户选择仅替换驱动回到 **1.9.0**，保留当前用户数据、EFI、身份和 GlideBeam。最终使用 **NVENC H.264 → Windows GPU 解码**；环境仍为 OpenCore 1.0.5、macOS 15.8.1（24H32）。升级前、1.13.0 后、最终 1.9.0 的三个完整冷备均通过 8 项 SHA256 复核，最终冷启动和远控恢复通过。过程见[1.13.0 验证及回退 1.9.0](docs/11-driver-upgrade-1.13.0.md)，后续按[通用升级流程](docs/12-driver-upgrade-runbook.md)执行。

[1.1.0 基线](results/observed-2026-10-09.json)、[1.9.0 历史升级](docs/09-driver-upgrade-1.9.0.md)和 [1.10.0 软件回退记录](docs/10-driver-upgrade-1.10.0.md)保留原有版本与范围。本仓库是安装记录和配置工具，不是 NVIDIA 驱动项目。

本轮脱敏结果：[1.13.0](results/observed-2026-10-11-1.13.0.json)、[最终 1.9.0 驱动回退](results/observed-2026-10-11-rollback-1.9.0.json)。

**版本选择：**1.9.0 恢复 H.264 硬编，但本轮 OpenCL 探针失败、HEVC 硬编像素错误，Apple 软件 H.264 → Mac 硬解也有明显误差。1.13.0 的小规模 OpenCL / 软件编码→硬解通过，但 3060 没有硬编，GlideBeam 使用 Apple 软件 H.264。这次选择优先保留 H.264 远控路径，具体取舍与两轮证据都保留在第 11 章。

**给 AI 使用：**先读根目录 [AGENTS.md](AGENTS.md)，再读 [AI 教材](docs/AI-GUIDE.md)和[机器索引](ai/knowledge.json)。教材末尾提供本地 / GitHub 阅读提示，可直接复制给接手的 AI。

## 当前 1.9.0 回退后的实测结果

| 项目 | 结果 | 范围 |
| --- | --- | --- |
| PCI 直通 | 通过 | RTX 3060 显卡和 HDMI 音频功能同时直通 |
| 显卡识别 | 12GB、Metal 3 | 系统报告和原生 Metal 设备枚举 |
| Metal | 通过 | 小缓冲区复制、运行时编译计算、64×64 渲染 |
| OpenCL | **探针失败，任务未运行** | `clSetKernelArg` 返回 `-49`；设备可枚举不代表正确性通过 |
| Mac H.264 硬件解码 | 输入兼容性有差异 | NVENC 输入的小样本通过；Apple 软件输入 Y MAE 11.377，不能宣称普遍正确 |
| HEVC / H.265 硬件解码 | 指定样本通过 | Apple 软件编码输入、1280×720、30 帧像素验收 |
| H.264 硬件编码 | NVENC 生产路径通过 | GlideBeam 30 帧颜色 / 移动标记测试，可见 1080 / 编码 1088 高度 |
| HEVC 硬件编码 | **像素失败** | API 成功但画面错误；不作为可用功能推荐 |
| 远程桌面 | GlideBeam NVENC H.264 → Windows GPU 解码通过 | 1920×1080、30 秒实际显示 1374 帧、后段采样约 56.5fps；本轮未注入输入 |
| 关机 / 重启 | 通过 | `-vsmccomp` 消除双 AppleSMC；关机使 QEMU 正常退出 |
| CPU | 10 核 20 线程可用 | ES 处理器的显示名称仍为 Unknown；部分 CPUID 信息显示 16/32 |

这些结果只覆盖下面这台机器和小规模验收，不能推导出所有 RTX 型号、应用、长时间负载或新版驱动都可用。RustDesk 的硬件编码能力还受客户端实现和 VideoToolbox 属性查询影响，不能仅凭“Metal 3”判断。

## 测试环境

| 组件 | 实际版本 / 配置 |
| --- | --- |
| 主板 / BIOS | ASRock B460M Pro4S/ac / P1.40 |
| CPU | Intel i9-10900K ES QTB2，10 核 20 线程 |
| GPU | RTX 3060 12GB，PCI ID `10de:2504`；音频 `10de:228e` |
| Unraid / 内核 | 7.3.2 / Linux 6.18.38 |
| QEMU / libvirt | 10.2.3 / 12.2.0 |
| 虚拟机 | Q35、OVMF pure EFI、16GiB 内存、20 vCPU、160GiB qcow2 |
| 显示器 | 显卡连接物理显示器；未验证 HDMI 假负载方案 |
| BIOS | Above 4G Decoding 已开启；没有找到 C.A.M. / Re-Size BAR 菜单 |
| BAR1 | 宿主机由 256MiB 调整到 8GiB，再启动虚拟机 |

## 按顺序安装

1. [准备硬件、BIOS、VFIO 和依赖](docs/01-prerequisites.md)。
2. [生成自己的 SMBIOS 身份和 OpenCore 配置](docs/03-opencore-and-identity.md)。这一步在首次开机前完成，以后保持身份不变。
3. [准备精确版本安装介质，安装 macOS](docs/02-installation.md)。
4. [调整 BAR、安装驱动、移除虚拟显示器](docs/04-gpu-driver-and-bar.md)。
5. [配置 VNC，验证关机和重启](docs/05-remote-and-power.md)。
6. [运行 Metal 和视频验收，排查常见问题](docs/06-validation-and-troubleshooting.md)。
7. [建立恢复点、回滚和发布 GitHub 仓库](docs/07-backup-and-publishing.md)。

已有 VM 更新先读[通用升级流程](docs/12-driver-upgrade-runbook.md)，本次 [1.10.0 → 1.13.0 验证及只回退驱动到 1.9.0](docs/11-driver-upgrade-1.13.0.md)记录固定资产、脚本审查、完整冷备与逐项验收。历史过程见 [1.9.0 → 1.10.0](docs/10-driver-upgrade-1.10.0.md)和 [1.1.0 → 1.9.0](docs/09-driver-upgrade-1.9.0.md)。

总体流程：

```mermaid
flowchart LR
    A[BIOS / VFIO] --> B[OpenCore + Recovery + VNC 虚拟显示器]
    B --> C[安装 15.8.1 / 移除 Recovery 盘]
    C --> D[开启客户机 SSH / VNC / 冷备份]
    D --> E[停止 VM / BAR1 8GiB / 驱动配置]
    E --> F[安装驱动 / GPU 接管 / 移除虚拟显示器]
    F --> G[Metal / 编解码 / 关机重启验收]
```

## 仓库内容

- `templates/`：从工作配置脱敏而来的 OpenCore 1.0.5 和 libvirt 模板，身份字段留空，Apple SMC OSK 使用占位符。
- `tools/configure.py`：生成本地身份配置，输出安装阶段或显卡阶段的 OpenCore / XML；不会连接服务器或修改运行中的 VM。
- `tools/check_publication.py`：检查待发布文件中的介质、私网 IP、已填身份、OSK、密码字段等。
- `scripts/unraid/`：建立 EFI 镜像、调整 BAR、VM 启动钩子、冷备份。
- `scripts/macos/`：基本验收和原生测试的编译入口。
- `tests/native/`：实际使用的 Metal / VideoToolbox 测试源码。
- `results/`：脱敏实测结论；不附原始私有日志。
- `AGENTS.md`、`docs/AI-GUIDE.md`、`ai/knowledge.json`：AI 阅读入口、教材和任务索引。

文档描述的硬件流程已在实机执行。导出的通用脚本经过离线测试和语法检查，**没有作为一套全自动安装器在另一台服务器完整重跑**。先阅读脚本的参数和前置条件，再在自己的机器执行。

本次文件与工具的具体检查范围见[导出检查记录](docs/08-export-validation.md)。

## 下载与授权

安装介质、EFI 二进制、驱动、固件和身份参数由使用者自行取得，不随本仓库分发。原始文档、辅助脚本和测试源码采用 [MIT License](LICENSE)；配置模板的来源和第三方许可证见 [NOTICE](NOTICE.md)。教程的 EFI 基础来自 [LongQT-sea/OpenCore-ISO](https://github.com/LongQT-sea/OpenCore-ISO)。

本仓库只在本地生成配置。真实序列号、MLB、UUID、ROM、MAC、密码和 OSK 放在被忽略的 `local/` 中。发布前请按[发布步骤](docs/07-backup-and-publishing.md)运行检查。
