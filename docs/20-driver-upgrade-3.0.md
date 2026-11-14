# 官方 3.0 升级：外置固件校验、探针兼容修复与全量 H.264 复验

日期：2026-11-14。当前驱动由官方 2.7.2 升级为 **官方 3.0**（无实验覆盖包）。本轮沿用用户此前“硬盘太大跳过备份”的明确选择，**没有新增整机冷备**；唯一整机恢复点仍为 `post266-480g-20261101`。官方安装器另外保留了完整的组件与旧固件回退。没有修改 EFI、Apple 身份、远控应用或 TCC。

上游跨版本变化很大：2.8 引入 NVIDIA 620.70.06 基线，2.9 更换 NVK、设置和可选功能体系，3.0 修复登录后 GPU 丢失、显示设置卡顿、旧 SDK 应用崩溃等问题。上述均为上游证据，不当作本机逐项验收；本机结论只来自下述安装后实测。

## 固定输入与安装前审计

- 目标：[v3.0](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v3.0)，解析提交 `5289b35091e199644a9a2e414ee6d463c6c4c401`，发布于 2026-11-14T00:33:07Z。
- 官方包：`nullmoth-nvidia-3.0.tar.gz`，68,836,145 字节，SHA256 `40f0390d0b7cda75637991879b09abb7f8f7e3e5db2e811196963b3a2cacbcad`。三方核对一致：GitHub API 资产摘要、发行随附 `SHA256SUMS.txt`（自身摘要 `d6fa09d8244db5c1c2683f9a288719f9d3fbc5005c11448ef7ee8f0c2232713f`）、Mac 下载后复验。
- 签名文件保留：`.sig` `e9f1483ec79ebb8d10e25053d11ce3973304901adedf27836cb3b4fb77dad189`，`.bsig` `aaa8eed6ac1e3af450b95aab0bce9e0cffec96c856e3a0dff9f1500e44ce2c95`。安装门槛仍是 SHA-256 三方一致。
- 归档审计：153 个条目，无绝对路径、无目录穿越；2 条 Vulkan 符号链接均指向包内；固定 `pkgroot/` 包裹布局；包内 `SHA256SUMS --strict -c` 86 项全部通过，安装器另确认全部文件均被清单覆盖；`VERSION` 为 3.0。
- 安装器与 2.7.2 的差异为 211 行新增、20 行删除，重点逐段审阅：
  - 在修改任何文件之前，从 NVIDIA 官方 Linux 驱动包提取并校验 620.70.06 固件；已有匹配安装可复用。
  - 保留用户设置、共享着色器缓存和旧固件回退；移除旧的 `NVIDIAShared.bundle` 与旧固件目录。
  - `gfxrst=4` 只在缺失且 WhateverGreen 加载时补写；本机已有该项，安装前后 `nvram boot-args` 字符串完全相同。
  - DLSS、Safari 专用副本、GPU boost 均为可选项，本轮没有启用；没有安装实验性混合显卡、HDR、VRR 或 Ray Tracing 开关。
- `CHECK=1` 预检退出码 0：`CHECK PASS (nothing changed)`。该预检在固件下载前结束，因此另做了下列固件预下载与提取校验，未把 CHECK=1 当作固件可用性的证明。
- 关键二进制 SHA-256 固定如下，安装后读回全部 `OK`：
  - NVRM `ba6184e9a092687692af1b9e16cff555c7c3f1d81c258c8c8b77273ed7cadf05`
  - NVRMFB `4d3c4c026629f8d3483411fd4209ffaff787edf6f45845ec75f4e0b76933a85d`
  - NVRMAGDC `97623c55c4a804fd5d4a5338d06672fe87f160576435853dc6b6e13505b325b9`
  - NVAccel（os26）`4b5020c65640357326d0a17aed316b1d13562c578a8d2ca83e0e9070821a8d56`
  - NMXAudio 1.0.0 `17c4804d6a253e1a779a4ec141cb7b9e0b3dc3199b67543aaece3974bb9a543d`
  - NVMTLDriver `7d2e06e65a5109acd9ab56a7435ac1f3845e68b5a1a232bb1969b5d0a880c113`
  - libnvencvt.dylib `80d70d613522c47dae2d7a14ac400cf44328ae1c9147e14adda7215c79b032d2`
  - libnvenc_h264.dylib `fb0cd5308c52072fedfdee0b83350294e8081d8628a6af99cb1230999ba73640`
  - libnvenc_h264_ga10x.dylib `92985c5286ddc5c5dfb77ec04ea3364d92524e461abf93fb3646c4fe302488cb`
- **两个 H.264 NVENC 库与 2.6.6/2.7.2 仍完全相同**；本轮只扩展探针的标签格式并保持 GA10x 绑定，没有改硬件要求、1920×1080 NV12 输入、独立软件解码、像素容差、强制 IDR 或性能门槛。

## 外置 GSP 固件预校验

v3.0 不再随包附带 GSP 固件。为避免安装中途联网失败，安装前单独下载并验证了上游 `fw_fetch.sh` 固定的 NVIDIA 包：

- `https://download.nvidia.com/XFree86/Linux-x86_64/620.70.06/NVIDIA-Linux-x86_64-620.70.06.run`
- 549,763,565 字节，SHA256 `29118e3abd08c07559bcca3d9c76238d039490af0362a2e5bcfcbe7204afd4b1`。
- 使用包内 `fw_fetch.sh --run` 在证据目录中预提取，四个成员全部通过固定摘要：
  - `gsp_ga10x.bin` `26a32926507e19e8c92911ed6a9b7981c9699c7a10bb78cc76b4f4abcbff84b6`
  - `gsp_tu10x.bin` `92af243e48c22325568ce24ef2edf5fa257b9bacc10a18fd38342cddeaf83fd8`
  - `ucodes_ga10x.bin` `b8f3d94d33cc284da4e0b758f069271818694b2ce8b50769d6a14b46df5d3cbf`
  - `ucodes_tu10x.bin` `db482009e834e26e901bfdf1f3428d1ab54b59b645ea9b987d0f6f14f4567a4f`
- 安装时通过 `NULLMOTH_FW_RUN` 提供同一份已校验 `.run`，没有依赖安装阶段的实时下载。安装后 `/Library/NullMoth/nvfw/nvidia/620.70.06/` 四个文件再次逐字节比对通过。

## 安装、回退与重启

- 安装标记：`INSTALL_STARTED` 2026-11-14T14:30:22Z，`INSTALL_COMPLETE` 14:31:43Z（约 81 秒）。
- 官方组件及固件回退：`/Library/NullMoth/backup-20261114-223126.TfZDH4`，约 772 MiB，包含 2.7.2 组件和旧固件（615.78.08、610.57.04）。回滚：`sudo ./uninstall.sh /Library/NullMoth/backup-20261114-223126.TfZDH4`。
- 无审批数据库警告，boot-args 未改变；安装器确认“已允许扩展的更新只需一次重启”。
- 重启后 SSH 于 22:35 恢复，22:36 控制台用户 mac 登录，bootguard 记录 WindowServer 持续 45 秒正常。NVRMFB / NVRMAGDC / NVRM / NVAccel 均为 **3.0**，NMXAudio 为 **1.0.0**；RemoteHost 随后恢复运行。
- 显示读回 1920×1080、RTX 3060 12 GB、**Metal 4**。音频只验证 NVIDIA HDMI/DP 设备枚举，没有验证声音内容或延迟。

## 探针兼容修复与失败记录

本轮不是直接复用旧探针就通过，以下两次失败均保留在证据目录中，没有改写为成功：

1. `acceptance-20261114T144033Z`：旧探针只接受 `vX.Y.Z`，上游实际标签为 **`v3.0`**，在创建编码会话前退出码 2。将标签正则扩展为允许两段或三段版本号。
2. `acceptance-20261114T144718Z`：目标编码器创建成功，但报告 `loaded_encoder_hash_unavailable`。仓库中的旧源码仍匹配通用 `libnvenc_h264.dylib`，与本机自 2.5.3 起绑定的 **GA10x 专用库**不一致；改为匹配 `libnvenc_h264_ga10x.dylib` 后重新构建。

最终探针在 VM 内以原有 Clang 参数编译并 ad-hoc 签名，`codesign --verify --strict` 通过：

- 新探针 SHA256 `6c037b5551e235bc340f03efc2485139b2fdef5ec7659cb40eb32328d2e1949e`
- 配套报告校验器 SHA256 `082bb21a664253ddc96fb0b57070e27e5a08d27809cdc1743ec0eab520e5edc3`
- 探针源码 SHA256 `5457a76d72ccdefe21aa52b4265e95f2e67115e799e86301ab3ef5ed6dbaa7ff`
- 准备 kit 的原二进制未修改；新增文件 root 所有且其他用户不可写。Python 校验器同步接受两段标签，新增单元测试；仓库单元测试共 64 项通过、2 项跳过。

## 实际验收

重启后等待负载降到探针门槛（load1 < 3）再执行；最终结果目录 `acceptance-20261114T145009Z`，`run-status` 读回 `exit_status=0`、`stage=complete`、`host_restore=restored`。

| 项目 | 结果 |
| --- | --- |
| Metal | 复制、计算、渲染全部通过，错误计数均为零；系统报告 Metal 4 |
| H.264 短测 | 30 帧硬件编码、独立软件解码、像素通过（32.475 FPS 为 30 帧含启动开销，不作持续性能门槛），编码 p95 3.096979 ms；校验器 PASS，报告 SHA256 `fb8eafcb6cc02796d11147585a92a6c51c8add3024e9dfdf6793f32a83b92b0a` |
| 持续硬编资格 | 3600 帧全部编码 / 解码 / 像素通过，回调错误 0、丢帧 0，59.997174 秒，**60.002826206 FPS**，编码 **p95 6.059582 ms**（p50 5.690901 / max 7.085391）；校验器 PASS，报告 SHA256 `73368fad39711b460a2d969a13846ffda2167fa7ff92259e139696f342f900bc` |
| 关键帧 | 强制关键帧 60、IDR 帧 60、强制 IDR 校验通过 60 |
| 编码器 | 请求与实际选择均为 `com.nvmtl.videoencoder.avc.nvenc`；hardware_required / hardware_used 均为真，software_fallback_allowed 为假；GPU 读回 vendor `0x10de`、device `0x2504`、单个 NVIDIA 显示设备 |
| 实际加载编码库 | `libnvenc_h264_ga10x.dylib`，SHA256 `92985c5286ddc5c5dfb77ec04ea3364d92524e461abf93fb3646c4fe302488cb`，与 2.7.2 及官方清单一致 |
| 解码侧 | 按探针规格禁用硬件解码（decoder_hardware_disabled_by_spec=true），硬件查询返回 -12900，像素校验走独立软件解码路径；这不构成硬件解码验收 |
| 光梭 | `--self-test-codec` 30 帧生产路径通过（hardware、status 0、像素断言通过、`nvenc_layout_workaround=False`）；验收后 RemoteHost 恢复运行 |
| 显示 | 读回 1920×1080；PiKVM 上限仍为 50 Hz，与编码资格 60 FPS 是两个范围 |

- 与 2.7.2 相比，编码 p95 从 2.828556 ms 增加到 6.059582 ms，仍明显低于 16.67 ms 门槛。只记录差异，不归因于某一个上游改动，也不宣称性能提升或稳定性结论。
- Metal 报告 SHA256 `1f72a8c796786a61c53fda8ce4ccc2a86577a641d5b1f3a87fa1f9604278a51c`。

## 边界与回退

- HEVC 仍未在本机做像素验收；2.9/3.0 新增的系统解码服务、4:2:2 纹理、DLSS、Vulkan、光追、HDR/VRR、混合显卡和实验性电源功能均未逐项验收。
- 音频只验证设备枚举；上游基线元数据仍将 macOS 26 标为未资格；本机证据不外推到其他机器、显卡或 macOS 版本。
- 结果绑定 v3.0（提交 `5289b350`）、上述官方包、NVIDIA 固件包、探针与全部二进制摘要；新发行包出现时不得沿用本轮结论。
- 回退：
  1. 组件与固件级：`sudo ./uninstall.sh /Library/NullMoth/backup-20261114-223126.TfZDH4` 回到官方 2.7.2；
  2. 整机级：**仅** `post266-480g-20261101`（2.6.6 + 480 GiB）。本轮没有更接近当前状态的新冷备；恢复前须再次核对实际磁盘库存。
- 用户尚未在本轮升级后通过光梭客户端实际重连确认；确认后再补记，且不把它当作任何未验收项的替代。