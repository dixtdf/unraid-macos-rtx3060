# 官方 2.6.6 升级：完整冷备份与全量 H.264 复验

日期：2026-11-01。与[第 17 章](17-driver-upgrade-2.5.3.md)按用户要求跳过新增备份不同，本轮按用户决定**先做完整 VM 冷备份再安装**，使用未修改的官方安装器及其自带组件回退机制。没有修改 EFI、Apple 身份、远控应用或 TCC。升级动机来自上游证据（非本机验证）：2.5.5 的关键帧同步帧标记修复（关系远控画面）、2.6.0 的单次重启升级、2.6.6 的签名发行包与安装修复。HEVC 仍不在本轮验收范围。

## 固定输入与安装前检查

- 目标：[v2.6.6](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v2.6.6)，提交 `470e391e8cf8d7e499cdabfa7f2daadb6e14bcfd`。
- 官方包：`nullmoth-nvidia-2.6.6.tar.gz`，264,205,469 字节，SHA256 `dbb0f5c2a18ccc97dfdf57ca14488b0ea713c15608f684a0a4283e88c676ab6e`。三方核对一致：GitHub API 资产摘要、发行随附 `SHA256SUMS.txt`（其自身摘要 `9932799274317c3614cfccfcad6d8d4b30f3bd2b0c3862fc0703b72a6849ce6c`）、Mac 下载后复验。上游本轮随包发布 `.sig` 签名文件（摘要 `757fafb276cc88e78faee3c1b2519ae64d58c99139133c00ff9e0c15c82d12f4`），已保留为证据；本机的安装门槛是 SHA-256 三方一致。
- 归档审计：128 个条目，无绝对路径与目录穿越，两条 Vulkan 符号链接均指向包内；归档为固定 `pkgroot/` 包裹布局；包内 `SHA256SUMS --strict -c` 74 项全部通过；`VERSION` 为 2.6.6。
- 安装器与 2.5.3 版本差异 168 行，逐行审阅为良性：nvfw 回滚加固、ACL 检查、kmutil 阻断诊断、KextPolicy CDHash 更新、许可复制。
- 包内 `BASELINE-IDENTITY.json` 将 macOS 26 标为上游"未资格"。按证据记录：这不阻止本机测试，也不允许跳过验收；本机结论只由下列实测产生。
- `CHECK=1` 预检（含实际启动盘断言与四 kext 测试集检查）退出码 0：`CHECK PASS (nothing changed)`。
- 关键二进制 SHA-256 固定如下，安装后读回全部 `OK` 且与包内清单一致：
  - NVAccel（os26）`de3222062e5d04d3ae4a20ca9c627e6d1707549f80752ade060e3b22b62eb532`
  - NVMTLDriver `d877d83cb8618efcd898b4e496136475cadcc94a747546463379fa2d5074535a`
  - libnvenc_h264.dylib `fb0cd5308c52072fedfdee0b83350294e8081d8628a6af99cb1230999ba73640`
  - libnvenc_h264_ga10x.dylib `92985c5286ddc5c5dfb77ec04ea3364d92524e461abf93fb3646c4fe302488cb`
  - 固件仍为 615.78.08，与 2.5.3 相同。

## 安装前完整冷备份

- 主机目录 `/mnt/disk1/vm/backups/macOS-26.7.1-RTX3060-TRIAL-pre266-20261101/`，完成标记 `COMPLETE.private.txt`。
- qcow2（虚拟 240 GiB / 实际 189 GiB）XFS reflink 复制，并做**源与克隆的全量 SHA-256 对比**：两侧均为 `ef5e383e83bdaebc583411a28af500885e73124bd9fcc81f469c28d9c10ac137`，一致；补上此前 final26 检查点缺全量摘要的短板。
- 同备：EFI raw、`UEFI-VARS.private.fd`、libvirt NVRAM fd（VM UUID `235d32a8-8b53-4009-8f0b-aeacc7f8b1f3`）、两份域 XML、qemu-img check 输出、reflink inode 独立性核验。
- 第一次尝试在 NVRAM 一步以 `Invalid cross-device link` 失败（`/etc/libvirt` 位于根文件系统，不能跨设备 reflink）：删除半成品目录、对该文件改用普通 `cp -a` 后**整体重跑**，没有混用部分状态。
- VM 停机约 28 分钟。备份完成后启动正常：当时四项驱动仍为 2.5.3，RemoteHost 自启，控制台用户 mac。

## 安装与重启

- 沿用已验收的 tarball + `install.sh` 路径（与 2.5.3 轮相同，不使用 1401 GUI 应用）。标记 `INSTALL_STARTED` / `INSTALL_COMPLETE` 为 VM 本地时间 14:15 / 14:16；结果标记 `OFFICIAL266_INSTALL_AND_KEY_PAYLOAD_READBACK_PASS`、`NO_APPROVAL_DB_WARNING`。
- 安装器保留的旧组件回退位于 `/Library/NullMoth/backup-20261101-141557.OgpVrH`（回滚：`sudo ./uninstall.sh <该目录>`）。
- 安装成功后正常重启，内核启动时间实际读回 2026-11-01 14:16:57（VM 本地时间）。`kextstat` 实测 com.nullmoth.NVRMFB / NVRMAGDC / NVRM / NVAccel 四项均为 **2.6.6**，无需重新批准 kext。上游"单次重启升级"声明在本机兑现为实测：一次重启后四项全部到位。

## 实际验收

重启后等待系统负载回落到探针门槛（<3）再执行；结果目录 `acceptance-20261101T062356Z`，`run-status` 读回 `exit_status=0`、`stage=complete`、`host_restore=restored`。

| 项目 | 结果 |
| --- | --- |
| Metal | 复制、计算、渲染全部通过，错误计数均为零；设备读回 NVIDIA GeForce RTX 3060 (NVMTL over NVK GA106-A)、12 GB |
| H.264 短测 | 30 帧硬件编码、独立软件解码、像素通过（0.892 秒，含启动开销，不作持续性能门槛）；校验器 PASS，报告 SHA256 `36bbda98ade7310ca613fbb73cb122f9a188fa17b34c9c6fefa356891836d2a5` |
| 持续硬编资格 | 3600 帧全部编码 / 解码 / 像素通过，回调错误 0、丢帧 0，59.995393513 秒，**60.004606841 FPS**，编码 **p95 2.598385 ms**（p50 2.400424 / max 3.347552），优于 2.5.3 的 p95 3.222460 ms；校验器 PASS，报告 SHA256 `8d797dbe4a302f6f84afb4eddeeaea5d30f92b8c6ad9cd88b573f381716348e1` |
| 关键帧 | 强制关键帧 60、IDR 帧 60、强制 IDR 校验通过 60 |
| 编码器 | `com.nvmtl.videoencoder.avc.nvenc`，请求与实际选择一致；hardware_required / hardware_used 均为真，software_fallback_allowed 为假 |
| 实际加载编码库 | `libnvenc_h264_ga10x.dylib`，SHA256 `92985c5286ddc5c5dfb77ec04ea3364d92524e461abf93fb3646c4fe302488cb`，匹配官方清单 |
| 解码侧 | 按探针规格禁用硬件解码（decoder_hardware_disabled_by_spec=true），硬件查询返回 -12900，像素校验走独立软件解码路径；这不构成硬件解码验收 |
| 光梭 | `--self-test-codec` 30 帧生产路径：mode=hardware status=0，VT 硬件查询 value=1，`GLIDEBEAM_30_FRAME_HARDWARE_PIXELS_PASS`，`nvenc_layout_workaround=False`；探针结束后 RemoteHost 恢复运行。用户升级后已经光梭客户端实际重连，确认远控体验正常（2026-11-01 用户确认） |
| 显示 | 读回 1920×1080 @ 50 Hz（PiKVM 上限，与用户先前说明一致）。显示器刷新率与合成编码资格的 60 FPS 是两个范围，不把探针结果写成当前远控画面稳定 60 FPS |

## 探针复用与失败记录

- 本轮**没有修改探针**：2.6.6 仍随包提供 `libnvenc_h264_ga10x.dylib` 且本机仍选择 GA10x 库，[第 17 章](17-driver-upgrade-2.5.3.md)适配好的 GA10x 匹配探针原样复用；硬件要求、1920×1080 NV12 输入、独立解码、像素容差、强制 IDR 与性能门槛全部保持原样。Metal 工具继续使用固定副本（SHA256 `83897afe6598efa468a511190851b80e34a0c65cd9a115141b41ad58f5a3a0b0`）。
- 工作站侧事故如实记录：Windows PowerShell 内联 SSH 命令被转义破坏，一次畸形命令在 VM 用户主目录产生 11 个杂散 `mkdir` 参数条目；已按 13:10–13:30 修改时间窗全部移入 `cleanup-quarantine-20261101/`（附 NOTE.txt，未触碰点文件，未删除任何文件），此后所有远程执行改为 LF 校验过的脚本文件传输后运行。事故发生在原生测试之前，未触及驱动，也没有为掩盖事故修改测试内容。隔离目录按用户要求保留。
- 冷备份第一次跨设备失败与整体重跑见上文；没有用部分备份冒充完整备份。

## 回退与保留

- 三级回退，须区分日期与范围：
  1. 组件级：`sudo ./uninstall.sh /Library/NullMoth/backup-20261101-141557.OgpVrH` 回到官方 2.5.3；
  2. 整机级：`pre266-20261101` 完整冷备份（2026-11-01 13:42 前状态，含 qcow2 全量摘要对比）；
  3. 更早检查点：final-20261019-01（26.7.1 + 2.3.7 覆盖时代）、15.8.1 VM 与 2.3.x 冷备份。
  回退时不把较旧系统镜像直接覆盖较新的用户数据。
- 按用户决定全部保留、不删除：隔离目录、官方回退组件、主机备份脚本，以及 `/Users/Shared/RemoteNative/trials/driver-2.6.6-20261101/` 下全部证据（tarball 与签名、pkgroot、scripts、验收目录、install.private.log、check1-266.log、key-binaries-266.sha256、installer-diff-vs-253.txt）。

## 后续边界

- HEVC 仍未在本机做像素验收；官方支持声明不当作本机通过。音频路径与端到端延迟本轮未另行重测。
- 上游 `BASELINE-IDENTITY.json` 仍将 macOS 26 标为未资格；本记录是本机（macOS 26.7.1 / 25G241 + RTX 3060 GA106 LHR，PCI `10de:2504`）的独立证据，不改变上游资格状态，也不外推到其他机器、显卡或 macOS 版本。
- 结果绑定 v2.6.6（提交 `470e391e8cf8d7e499cdabfa7f2daadb6e14bcfd`）与上文全部摘要；新发行包出现时不得沿用本轮结论。
- 用户已于升级当日（2026-11-01）通过光梭客户端实际重连并确认远控体验正常；该确认记录为用户主观体验，不替代上文任何未验收项，用户对 2.3.7 / 2.5.3 的既往确认也不与本次混同。
