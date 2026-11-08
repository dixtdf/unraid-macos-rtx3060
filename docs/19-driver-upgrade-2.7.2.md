# 官方 2.7.2 升级：跳过新增冷备下的全量 H.264 复验

日期：2026-11-08。当前驱动由官方 2.6.6 升级为 **官方 2.7.2**（无实验覆盖包）。本轮按用户明确要求**不新增整机冷备份**：备份脚本已启动到全量哈希阶段后被用户叫停，半成品目录随即删除，回退深度因此低于第 18 章；保留的整机恢复点仍为 11 月 1 日的 `post266-480g-20261101`。官方安装器自带的组件回退在 VM 内新生成。本轮没有修改 EFI、Apple 身份、远控应用或 TCC。

## 固定输入与安装前审计

- 目标：[v2.7.2](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v2.7.2)，解析提交 `18ba05f38b5eadea8b5ae05834bb51c61fb4c5c3`，发布于 2026-11-05T07:34:07Z。
- 官方包：`nullmoth-nvidia-2.7.2.tar.gz`，264,616,298 字节，SHA256 `928557fece27637b1184f5655833566e7d516b22708cc341b28d555055d8e50e`。三方核对一致：GitHub API 资产摘要、发行随附 `SHA256SUMS.txt`（自身摘要 `3cc2fb39cdc3be5d62a6b69389296b3a2aff0b1d4f55b98f0970d71933ee6cc6`）、Mac 下载后复验。
- 随包签名文件已保留：`.sig` `378e8d966777538ddb300bf65dea9fec23cfcc704c3843913ca9779a6630ac0f`，`.bsig` `f9a09cf8b38ae89737a1101f0ec8442daca921b2a887e4b6c168d0ab9e585eff`。安装门槛仍是 SHA-256 三方一致，签名文件只作证据保留。
- 归档审计：134 个条目，无绝对路径、无目录穿越；2 条 Vulkan 符号链接均指向包内（`libvulkan.1.dylib -> libvulkan.1.4.362.dylib`、`libvulkan.dylib -> libvulkan.1.dylib`）；固定 `pkgroot/` 包裹布局；包内 `SHA256SUMS --strict -c` 77 项全部通过；`VERSION` 为 2.7.2。
- 安装器与 2.6.6 的差异仅 43 行，逐行审阅为良性：
  - macOS 26 且 PCI 上存在 HD Audio 控制器（`class-code 00030400`）时，把新增的 `NMXAudio.kext` 加入安装与内核集合；macOS 26 不再自带 HD Audio 驱动，15 不受影响。
  - 安装末尾 `chmod 755 /Library/NullMoth`，修复 2.7 中 ARM 翻译器 `nm-arm` 对普通用户不可达的问题；本机不使用 ARM 翻译器。
  - 卸载器同步把 `NMXAudio` 纳入回退范围。
  - 没有新增 EFI、SIP、身份、TCC 或远控相关改动。
- `CHECK=1` 预检退出码 0：`CHECK PASS (nothing changed)`。
- 关键二进制 SHA-256 固定如下，安装后读回全部 `OK` 且与包内清单一致：
  - NVRM `4aeb8a5ed67ecfc593ae95474de1a67fda1ea6afc6b741de0fdbfb64583577d9`
  - NVRMFB `0c3b6f40bd3a6be381ed6704de987d3bed4bb22fa85fea76a195a6d6bafac534`
  - NVRMAGDC `c90a08aff583708210df392be3ac21a1682126304b40b5afa43958077eb5619f`
  - NVAccel（os26）`ba056eb32d9a0aa9aad736da79ace069f2bdd826153c4275e7d0bd6f08c99b21`
  - NMXAudio（新增，版本 1.0.0）`77e19e244978ce64e4505c4701069edfe609379f91a9c76313b4a27ded4ab07a`
  - NVMTLDriver `1eb7ce5b0aab1b39f1c53d2f90826088db21e4d554a8ff4290670d8083a5af6c`
  - libnvenc_h264.dylib `fb0cd5308c52072fedfdee0b83350294e8081d8628a6af99cb1230999ba73640`
  - libnvenc_h264_ga10x.dylib `92985c5286ddc5c5dfb77ec04ea3364d92524e461abf93fb3646c4fe302488cb`
- **两个 NVENC 库与 2.6.6 完全相同**，固件仍为 615.78.08；本轮探针因此原样复用，未改硬件要求、1920×1080 NV12 输入、独立软件解码、像素容差、强制 IDR 或性能门槛。2.7.2 的改动集中在 Metal/I/O 与安全修复，不在 H.264 编码路径。
- 包内 `BASELINE-IDENTITY.json` 的资格样本仍是 macOS 15.8.1 + RTX 5060，不把该样本当作本机 26 + GA106 的通过依据。

## 备份决定与主机侧插曲

- 用户在备份进行中明确要求：“硬盘太大跳过备份，如果已经备份请删除”。当时 VM 已优雅关机，源镜像 `qemu-img check` 通过、480 GiB 虚拟大小断言通过、reflink 复制与 inode 独立性检查均已完成，正在做全量 SHA-256 对比。按指令终止脚本，并删除半成品目录 `/mnt/disk1/vm/backups/macOS-26.7.1-RTX3060-TRIAL-pre272-20261108/`；没有留下任何未验证的“备份”。
- 因此**本轮没有新的整机冷备**，唯一整机回退点仍是 `post266-480g-20261101`（2.6.6 + 480 GiB，11 月 1 日全量哈希验证）。它比安装前状态早 7 天，且与活动镜像同在一块物理盘上，不是异地副本；这是用户知情后接受的恢复深度下降。
- 组件级回退由官方安装器新生成：`/Library/NullMoth/backup-20261108-094635.vEkHlk`（约 770 MiB，含 2.6.6 内核集合与用户态 bundle）。
- 主机侧发现并修复一个与 2.7.2 无关的潜在问题：关机后首次 `virsh start` 失败，原因是 `/etc/libvirt/hooks/qemu.d/50-macos-rtx3060-bar` 仍把 BAR 日志写入已删除的 `macOS-15.8.1-RTX3060` 目录（该 VM 已于 11 月 1 日删除，这个 hook 此前一直未再触发）。修复为只匹配 `macOS-26.7.1-RTX3060-TRIAL`，日志改写到本 VM 目录；BAR 调整逻辑不变。第一次把旧 hook 备份为同目录的 `.bak-20261108` 时，libvirt 仍会执行目录内每个可执行文件，旧副本再次触发失败；把备份移到 `/root/nvidia-upgrade-20261108/` 后启动成功。该修复不改变 GPU 直通或 BAR 结果。

## 安装与重启

- 安装标记：`INSTALL_STARTED` 2026-11-08T01:46:03Z，`INSTALL_COMPLETE` 01:46:52Z（约 49 秒）。
- 安装输出：包完整性、测试内核集合、备份、替换全部通过；**`NMXAUDIO_INSTALLED`**；无审批数据库警告。安装器提示“若 macOS 询问，请在系统设置中允许扩展”，但本机 SIP 为自定义配置、Kext Signing 已禁用，重启后 `NMXAudio` 与四项 NVIDIA kext 一起直接加载，无需额外 GUI 批准。
- 正常重启后 `kextstat` 实测五项：NVRMFB / NVRMAGDC / NVRM / NVAccel 均为 **2.7.2**，NMXAudio 为 **1.0.0**；`/Library/NullMoth/driver-version` 为 2.7.2，`os-major` 为 26。bootguard 记录桌面正常起来。
- 音频枚举已出现三个 `NVIDIA (0x009f) (HDMI/DP 8ch)` 设备，制造商 `NullMoth`；**只验证了设备枚举，没有做音频内容、声道或延迟验收**。BlackHole 2ch 仍是默认输入/输出。

## 实际验收

重启后等待负载降到探针门槛（load1 < 3）再执行；结果目录 `acceptance-20261108T015335Z`，`run-status` 读回 `exit_status=0`、`stage=complete`、`host_restore=restored`。

| 项目 | 结果 |
| --- | --- |
| Metal | 复制、计算、渲染全部通过，错误计数均为零；设备读回 NVIDIA GeForce RTX 3060、12 GB、Metal 3 |
| H.264 短测 | 30 帧硬件编码、独立软件解码、像素通过（29.800 FPS 为 30 帧含启动开销，不作持续性能门槛）；校验器 PASS，报告 SHA256 `b6e4556b851f12d2be69eeac498ae8415011ef90676e780bf0c8cfe1bc5d44bd` |
| 持续硬编资格 | 3600 帧全部编码 / 解码 / 像素通过，回调错误 0、丢帧 0，59.996 秒，**60.003952092 FPS**，编码 **p95 2.828556 ms**（p50 2.489212 / max 3.894243）；校验器 PASS，报告 SHA256 `4f859fdc31341a97b0177eac0dc43ca58a008c27be43534dbce958537a3a7f1a` |
| 关键帧 | 强制关键帧 60、IDR 帧 60、强制 IDR 校验通过 60 |
| 编码器 | 请求与实际选择均为 `com.nvmtl.videoencoder.avc.nvenc`；hardware_required / hardware_used 均为真，software_fallback_allowed 为假；GPU 读回 vendor `0x10de`、device `0x2504`、单个 NVIDIA 显示设备 |
| 实际加载编码库 | `libnvenc_h264_ga10x.dylib`，SHA256 `92985c5286ddc5c5dfb77ec04ea3364d92524e461abf93fb3646c4fe302488cb`，与 2.6.6 及官方清单一致 |
| 解码侧 | 按探针规格禁用硬件解码（decoder_hardware_disabled_by_spec=true），硬件查询返回 -12900，像素校验走独立软件解码路径；这不构成硬件解码验收 |
| 光梭 | `--self-test-codec` 30 帧生产路径通过（hardware、status 0、像素断言通过、`nvenc_layout_workaround=False`）；验收后 RemoteHost 恢复运行 |
| 显示 | 读回 1920×1080；PiKVM 上限仍为 50 Hz，与编码资格 60 FPS 是两个范围 |

- 与 2.6.6 相比，p95 从 2.598 ms 变为 2.829 ms（+0.23 ms），仍在 16.67 ms 门槛内；由于加载的编码库哈希完全相同，不把这 0.23 ms 归因于 2.7.2，也不宣称性能提升或回归。
- Metal 报告 SHA256 `617d24edb024d5e03fea2d972d79abd6e55305ec7a0b96333686b104a2157c5e`。

## 边界与回退

- HEVC 仍未在本机做像素验收；音频只验证枚举；2.7.2 的 Metal 修复、安全修复（内核竞争、地址泄漏、profiling 权限）与 AMD/Intel 测试驱动不在本机逐项验收范围；上游基线元数据仍将 macOS 26 标为未资格。
- 结果绑定 v2.7.2（提交 `18ba05f3`）、上述包与二进制摘要；新发行包出现时不得沿用本轮结论。
- 回退：
  1. 组件级：`sudo ./uninstall.sh /Library/NullMoth/backup-20261108-094635.vEkHlk` 回到官方 2.6.6；
  2. 整机级：**仅** `post266-480g-20261101`（2.6.6 + 480 GiB）。本轮没有更接近安装前状态的新冷备；恢复前须再次核对实际磁盘库存，不能按已删除路径尝试。
- 用户尚未在本轮升级后通过光梭客户端实际重连确认；确认后再补记，且不把它当作任何未验收项的替代。