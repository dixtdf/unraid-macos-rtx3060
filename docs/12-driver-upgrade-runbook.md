# 12. 通用驱动升级流程与 AI 交接

本流程用于已有 Unraid / QEMU macOS VM 的 NullMoth 更新。每次更新建立独立恢复点、独立资产清单和独立实测结果；已有安装的身份、EFI、硬件拓扑与远控授权以现场配置为准。它不替代首次安装教程，也不保证下一版驱动的行为与上一版相同。

执行者先阅读根目录 [AGENTS.md](../AGENTS.md)、[AI 教材](AI-GUIDE.md)、[机器索引](../ai/knowledge.json)、最近一轮完整升级记录及本次官方 release。用户已授权的升级范围持续有效；有功能取舍时依据新的实际影响处理，不把旧版本结论写成本次现场结果。

## 1. 固定目标和只读盘点

给本轮记录一个唯一名称，例如 `driver-<目标版本>-<时间>`，记录本地时间和 UTC。先确认实际安装版本、macOS build、OpenCore、CPU / 内存、PCI 归属、BAR1、SMC 服务、显示模式、VM 状态和存储空间。查找真正启动的 EFI、系统盘、NVRAM 和 XML，而不是根据教程中的范例路径猜测。

列出所有附加磁盘及 qcow2 backing chain：系统盘、EFI、仍挂载的安装 / delivery 盘、其他可写盘、外部快照链。临时盘是否可移除必须先查清用途；不要为了凑“固定备份文件数”漏掉本轮新增的盘。

远控方面确认 SSH、VNC、GlideBeam 实际构建来源、运行中的 Mac 主机应用、编码器模式和 Windows 解码器状态。保留原配对、签名身份、屏幕录制与辅助功能授权。应用显示的版本号可能没有变化，需另记提交或二进制摘要。

将初始状态和原始日志放私有目录。现有 VM 不重新运行身份初始化，不重新生成 UUID、网卡 MAC、ROM、SSN、MLB，也不默认更改 CPU、SIP、boot-args 或 NVRAM。

**完成条件：**升级目标明确；当前版本和存储依赖已确认；远程救援入口及可用空间已核对；没有遗漏的可写盘或 backing file。

## 2. 阅读固定 release 和审查安装包

查阅本次固定 tag 的发布说明、相关源码和已知问题，特别确认本机 GPU 架构的编码器注册、硬件视频内存布局、显示、OpenCL、Metal、权限 / SIP 和内核集合要求。上游说“支持”与本机测试通过分别记录；不要使用 `latest` 或依据发布日期替代版本号。

在实际下载机器上取得官方固定资产。先保存 release URL、资产名、大小、官方 digest（如果提供）、本地 SHA256 和对应源码 tag / commit。下载受阻时优先使用用户提供且该机器可达的代理；另一台机器的 `127.0.0.1` 不能直接代用。

下载与检查可以参照下列模板。变量必须从本轮可信资料填入；空值会停止，不能改成下载后才计算的摘要来假装匹配官方 digest。官方没有 digest 时，明确记录“本地首次摘要”，不要标为官方校验。

```bash
set -euo pipefail
: "${ASSET_URL:?填入本次固定官方资产 URL}"
: "${ASSET_NAME:?填入本次资产文件名}"
: "${EXPECTED_BYTES:?填入官方资产大小}"
: "${EXPECTED_SHA256:?填入可信的固定摘要}"

curl -fL --retry 3 "$ASSET_URL" -o "$ASSET_NAME"
# 需要代理时，在实际下载机器上为 curl 添加 -x "$DOWNLOAD_PROXY"。
test "$(wc -c < "$ASSET_NAME" | tr -d '[:space:]')" = "$EXPECTED_BYTES"
printf '%s  %s\n' "$EXPECTED_SHA256" "$ASSET_NAME" | shasum -a 256 -c -
```

先列出归档内容，审查绝对路径、`..`、符号链接 / 硬链接、解压路径和意外文件，再解压到本轮新的私有目录。检查 manifest 的路径限定在该包内，再校验全部项，记录真实项数。不要沿用旧包的 54 项或 43 项作为新包的固定预期。

阅读全文 `install.sh` / `uninstall.sh`，与当前版本比较：安装目的路径、所有替换和删除操作、旧组件备份、plist / 配置、驱动权限、kext / KC、失败退出和重启要求。安装器自身备份只覆盖它知道的组件，不能代替 VM 冷备份。不要未经检查执行一键脚本。

**完成条件：**固定资产可定位、摘要与来源明确、包内 manifest 完整通过、实际脚本已审查、对远控和其他已有功能的影响已明确。

## 3. 建立升级前完整冷备份

通过 macOS 正常关机；确认 libvirt 为 `shut off`、QEMU 已退出、相关磁盘无占用后才开始复制。备份期间 VM 必须持续停止，备份工具应拒绝运行中的 VM，并在结束前再次检查状态。不能使用 `virsh destroy` 掩盖客户机关机故障。

冷备份清单以现场为准：

仓库的 [checkpoint.sh](../scripts/unraid/checkpoint.sh) 只覆盖模板的两块磁盘、NVRAM 和 XML，不自动包含额外磁盘、backing chain、固件或宿主机钩子，也不执行本流程要求的全清单再读取校验。使用前按现场审查并补齐；不能将它打印的 `complete` 直接当作本流程全部完成。

| 内容 | 保存要求 |
| --- | --- |
| 所有可写虚拟盘 | 系统、EFI、附加盘及实际挂载的临时盘；目标必须是独立 inode |
| qcow2 backing chain | 保存完整依赖链并核对备份可解析的路径；只有顶层盘不足以恢复 |
| NVRAM 与固件 | 每台 VM 的实际 VARS 文件和所用 CODE 固件 / 版本 |
| VM XML | 当前持久配置；若运行态与持久态不同，分别保存并说明 |
| 宿主机配置 | BAR 配置、QEMU 钩子、Unraid 启动脚本及本轮依赖 |
| 远控应用和配置 | 当前 Mac 主机应用、配套客户端来源、签名身份及必要私有配置 |
| 环境和校验清单 | 版本、文件清单、backing chain、源 / 备份检查、SHA256、时间和检查结果 |

在停止状态对源 qcow2 运行 `qemu-img check` 并检查 backing chain，再复制到新的恢复点。可用 reflink 节省空间，但必须确认文件为独立 inode；硬链接不是冷备份。检查备份 qcow2，确认它引用的是保存好的依赖而非将来可能改变的原盘。

生成全文件 SHA256 清单后，再实际读取备份执行完整校验。记录“全部文件 / 总项数”与每个失败项；不要只校验清单文件本身，也不要把复制工具退出 0 写成摘要复核通过。空间不足、链缺失、磁盘检查失败或校验失败时先处理，不能把不完整恢复点标为可恢复。

保留旧恢复点和旧安装包。私有交接里保存真实恢复路径与校验日志，公开结果只保存范围、数量和结论，不发布镜像、XML、EFI、SMBIOS、凭据或未脱敏日志。

**完成条件：**VM 全程停止、磁盘和依赖齐全、源 / 备份检查通过、所有摘要再读取通过、恢复路径明确、旧恢复点仍在。

## 4. 安装并正常重启

完成冷备后启动原 VM，重新确认 SSH / 独立救援入口。在 macOS 本轮私有目录中运行已经审查且完成 manifest 校验的官方安装器。保存完整私有输出、退出码和它打印的组件备份位置；密码通过已授权凭据机制或隐藏输入提供，不能写到公开脚本、日志和命令范例中。

核对试建内核集合、旧组件备份、安装完成等实际阶段。失败时保留现场并定位原因，不能因后续某条命令成功而忽略前面错误。只有安装成功且按新包要求处理完成，才通过客户机正常重启。

等待 SSH 恢复、客户机版本明确。不要默认清 NVRAM、替换身份、重新初始化 EFI 或强行断电；需要恢复时使用上一阶段完整恢复点。

**完成条件：**安装器成功且旧组件位置已记录；客户机正常重启；SSH 恢复；没有未处理的安装错误。

## 5. 重启后逐层验收

先核对已安装文件与本包 manifest，再核对运行中的组件。记录匹配的实际 payload 项数、已加载 kext、用户态 Metal / 视频组件和设备信息。某些版本的 `CFBundleVersion` 不随安装包版本变化，不能仅据它判定是否升级成功。

比较升级前后的 EFI 与 XML 摘要，说明有意修改。NVRAM 随启动发生自然变化时单独记录，仍以同一冷备份中的 VARS 文件用于完整恢复。按完整 IOService 类名统计 SMC：本参考配置期望 1 个 AppleSMC / 0 个 VirtualSMC 服务；kext 加载与重复服务是不同证据。

在仓库根目录运行基础原生测试：

```bash
bash scripts/macos/verify-system.sh
bash scripts/macos/run-native-tests.sh
mkdir -p local/native-tests
clang -std=c11 -O2 -Wall -Wextra -Wno-deprecated-declarations \
  tests/native/opencl-acceptance.c -framework OpenCL \
  -o local/native-tests/opencl-acceptance
local/native-tests/opencl-acceptance
```

逐项阅读报告；有些测试退出 0 表示成功输出报告，并不表示报告中的全部路径通过。

| 验收项 | 必须保存的证据 |
| --- | --- |
| PCI / BAR / 显示 | GPU、音频、实际驱动、BAR1 大小、显示模式、可见内容 |
| Metal | 缓冲区复制、运行时编译计算、渲染像素三项结果 |
| OpenCL | 向量和局部内存 / barrier 归约的样本规模、设备、错误数 |
| H.264 硬编 | 强制硬编创建状态、实际硬件标志、帧数、解码后像素 |
| HEVC 硬编 | 同上，独立记录，不套用 H.264 结果 |
| H.264 / HEVC 硬解 | 软件编码产生输入，强制硬解并核对硬件标志、帧数和像素 |
| GlideBeam | 实际 Mac 编码器、配套 Windows 解码器、真实持续视频、重连与已测输入 |
| VNC | 认证、framebuffer 更新、可见桌面分别记录；黑帧不算桌面通过 |
| 重启 / 关机 | 重启后 SSH 和 GPU 恢复；正常关机后 QEMU 确实退出 |

视频结果分为“未测试”“创建不可用”“API 成功但像素失败”和“指定样本像素通过”。记录分辨率、profile、可见 / 编码高度、帧数、硬件标志、错误码与 Y / UV 误差。硬编注册恢复不等于帧布局正确，API 成功也不等于内容正确。不要把 `-12908` 的不可用写成已经产出错误像素。

GlideBeam 额外记录 Mac 应用 / Windows 客户端提交、二进制摘要与签名是否延续。信息面板应分列 Mac 编码与 Windows 解码。原生编解码通过后仍测试生产路径：采集格式、帧内存布局、实际尺寸、首帧 / 连续回调、重连、采样帧率和解码器。提交条数、实际显示帧数、网络 RTT、首帧时间和端到端输入延迟分别记录。

**完成条件：**形成逐项通过 / 失败 / 未测列表及范围；没有用 API、版本号或旧结果替代像素与实际远控验证；客户机正常电源路径已测试。未测试的长时间负载、其他显卡、HDR、4K 或完整 OpenCL 兼容性继续标为未知。

## 6. 建立升级后恢复点并再开机

验收后正常关机，重复第 3 步为新版本建立独立的完整冷备份，重新检查源 / 备份 qcow2 和全部 SHA256。升级前备份必须保留，不能只保留新版本恢复点。

冷备完成后再启动，核对 SSH、GPU、桌面登录和自动启动的远控主机，再检查当前实际编码模式。应用登录启动与 VM 自动启动是不同设置；不要为了本次测试顺带更改宿主机自动启动策略。

**完成条件：**新恢复点完整通过，旧恢复点仍可恢复；再次冷启动后必要远程入口和 GPU 功能可用。

## 7. 回滚与失败记录

安装或验收失败时记录失败版本、阶段、错误码、具体样本和目前仍可用的入口。先保存当前失败状态，不覆盖唯一恢复点。

如果用户希望仅回退驱动并保留现有用户数据，可以在完整冷备后采用已经审查且本版安装器明确支持的 payload 替换方式。它与恢复旧系统盘是两件事：旧 VDisk 的完整恢复也会恢复当时的数据状态，不能为了一次驱动降级默认丢弃较新的数据。不同版本的 manifest / Library payload 数量可能不同；验证目标版本的原始资产、完整 manifest、安装后摘要以及真实版本 marker，再重新完成全部功能与电源验收。不要推定所有未来安装器都支持 `--payload`，也不要手工改 marker 假装 payload 已匹配。

在 VM 停止、QEMU 退出、无磁盘占用时，逐一核对恢复目标路径，恢复同一个完整检查点的系统盘、backing chain、附加盘、EFI、NVRAM、XML、固件和配套宿主机配置，再恢复匹配的远控应用。不要混用不同时间点的系统盘、EFI 与 NVRAM。

`uninstall.sh` 的实际作用依据本次脚本审查结果判断：移除驱动和重建 KC 不等于自动恢复旧版组件。需要回到已验证状态时，完整冷备份是确定的恢复依据。回滚后仍重新验证版本、组件、GPU、远控和正常电源路径。

## 8. 写入独立结果并交接给 AI

每轮新建 `docs/NN-driver-upgrade-<版本>.md` 与 `results/observed-<日期>-<版本>.json`；更新 README、AI 教材和索引指向最新已验证结果。旧文件保留，不把历史结论覆盖成新版。实测、上游声明、源码推断、失败和未测试明确分开。

机器可读记录至少包括以下字段；值从本次现场证据填入，未测试使用 `null` 和说明，不能默认写 `true`：

```json
{
  "schema": 1,
  "recorded_date": "<日期>",
  "source_version": "<升级前版本>",
  "target_version": "<目标版本>",
  "package": {
    "release_url": "<固定 release>",
    "asset_url": "<固定资产>",
    "bytes": null,
    "sha256": "<本地 SHA256>",
    "digest_source": "<官方 digest 或本地首次摘要>",
    "manifest_entries_verified": null,
    "installed_payload_entries_verified": null
  },
  "installation": {"completed": null, "exit_code": null},
  "checkpoints": {
    "before": {"complete": null, "qcow2_pass": null, "sha256_files_verified": null},
    "after": {"complete": null, "qcow2_pass": null, "sha256_files_verified": null},
    "previous_retained": null
  },
  "validation": {
    "metal": null,
    "opencl": null,
    "h264_hardware_encode": null,
    "hevc_hardware_encode": null,
    "h264_hardware_decode": null,
    "hevc_hardware_decode": null,
    "glidebeam_actual_encoder_mode": "<硬编 / 软件 / 未上报>",
    "glidebeam_live_video": null,
    "warm_reboot": null,
    "normal_shutdown_qemu_exit": null,
    "post_checkpoint_cold_start": null
  },
  "failures_and_unverified": []
}
```

在实际结果中展开样本规模、硬件标志、像素指标、真实显示帧数、GlideBeam 构建来源和限制，不能只保留聚合布尔值。真实备份路径、身份、密码、配对信息、完整日志和截图位置写入私有交接文件，不写入公开 JSON。

发布前运行仓库要求的检查：

```bash
python -m unittest discover -s tests -v
python tools/check_publication.py
git diff --check
# 对本次修改的 shell 脚本运行 bash -n；有 OpenCore 修改才额外运行对应官方 ocvalidate。
```

人工复核公开域名、截图和 Git 历史。只提交教程、测试源码和脱敏结果；驱动包、镜像、已填身份的配置和私有日志保持私有。说明实际提交 / 推送状态，不把本地修改写成已经发布。

可直接交给后续 AI：

```text
请先读取 AGENTS.md、docs/AI-GUIDE.md、ai/knowledge.json、最新实测结果，
然后阅读全文 docs/12-driver-upgrade-runbook.md 与上一轮升级章节。
本次目标是升级到 [填写固定版本]。先只读确认当前机器与上一轮基线差异，
阅读固定 release / 源码 / 包内脚本，建立可恢复且完成完整 SHA256 复核的冷备份。
保留已有 VM 身份和 EFI，按本流程安装、正常重启、逐项验证图形 / 视频像素 /
实际远控与电源路径，建立升级后冷备并再次启动。每个失败和未测项照实记录。
生成本轮独立文档、脱敏 JSON 和私有交接，保留旧结果与恢复点；依现有授权完成发布。
```
