# 6. 验收与常见问题

每次修改 EFI、XML、驱动、BAR 或身份后分别验证，不要把“能看到桌面”当作全部完成。本次脱敏结论在 [results/observed-2026-10-09.json](../results/observed-2026-10-09.json)。

## 基础检查

```bash
bash scripts/macos/verify-system.sh
```

应看到 macOS 15.8.1 / 24H32、16GiB、10 核 / 20 线程、RTX 3060 12GB / Metal 3、1 个 AppleSMC、客户机 VNC 监听。网卡检查 `en0` 与 `IOBuiltin=Yes`。若输出有多个接口，逐个对应名称，不要只看第一条 `IOBuiltin`。System Profiler 输出也可能包含显示器序列号，公开前再检查，不直接上传完整原始日志。

## 原生 Metal 与视频像素验收

把本仓库复制到 macOS，在已安装 Apple Command Line Tools 的情况下：

```bash
bash scripts/macos/run-native-tests.sh
```

首次缺少 clang 时可通过 `xcode-select --install` 完成安装；脚本不会自动下载工具。结果写入被忽略的 `local/native-tests/`。

`metal-acceptance.m` 枚举设备并选择 NVIDIA，验证缓冲区复制、运行时编译的 256 元素计算及 64×64 渲染像素。本次三项均通过。它没有测完整 Metal 一致性、大规模分配、游戏 / Blender / 浏览器 / 长时间稳定性。

`video-acceptance.m` 使用强制硬件或强制软件的 VideoToolbox 编码，再分别要求硬件 / 软件解码，与原始彩色 YUV 帧比较平均绝对误差（MAE）。**进程退出 0 只表示生成了报告，不表示所有编码路径通过。** 必须同时检查 API 状态、实际硬件标记、输出帧数和像素误差。

| 输入路径 | 解码路径 | 本次结论 |
| --- | --- | --- |
| H.264 硬件编码 | 硬件解码 | 短片段像素验收通过 |
| H.264 软件编码 | 硬件解码 | 通过 |
| HEVC 硬件编码 | 硬件 / 软件解码 | **失败**：API 成功但 MAE 约 120–125，画面错误 |
| HEVC 软件编码 | 硬件 / 软件解码 | 通过；硬件解码 MAE Y≈0.144、UV≈0.082 |

验收为 1280×720、30fps、3 帧，不代表 4K、HDR、低延迟、长片段、所有 profile 或所有软件已验证。HEVC 硬件编码不能列为“支持成功”。H.264 还观察到码率控制参数被接受，但驱动使用固定 QP 23，并没有据此验证实际码率调节。

另一个兼容问题：强制硬件的 `VTCopySupportedPropertyDictionaryForEncoder` 返回 `-12908`，虽然创建会话后的属性字典能查询。这会影响依赖前置能力探测的第三方程序。

## 排障顺序

| 现象 | 先检查 | 已验证的处理 / 边界 |
| --- | --- | --- |
| 总是进入 Recovery | XML 附加磁盘、OpenCore picker | 安装完成后移除 Recovery 盘，保留 EFI 和系统盘 |
| `EB.MM.AKMR` / `EB.M.BAPr2 Err(0xE)` | 实际引导 config | `ProvideCustomSlide=true`；不要盲目指定 slide=0 |
| PCI 识别但显卡没有加速 | boot-args、SIP 数据、IONDRVSupport、kext / KC、Metal 注册 | 按驱动章节逐项验证，不仅看 PCI 名称 |
| 启动慢、分配失败 | 宿主机 BAR1、MMIO、GPU 是否已被占用 | 实测 8GiB BAR1 有效；调整必须发生在 VM 启动前 |
| Unraid VNC 黑屏 | 显卡是否已接管 | 改用客户机 VNC；确认物理显示器与输出 |
| 客户机 VNC 不通 | IP、5900 listener、共享授权、DSM / 地址格式 | 先网络后认证；不要同时改驱动与远控客户端 |
| 关机后 QEMU 不退出 | AppleSMC IOService 数量、panic 日志 | 保留 QEMU SMC，加入 `-vsmccomp`，重新验证 |
| CPU 显示 Unknown / 16 核 | ES 型号、sysctl 实际核数、QEMU APIC 信息 | 实际 10 / 20；目前名称未修复，无需加入失败的伪装 |
| 鼠标键盘消失 | XHCI ports、USB 控制器 / 输入设备 | 保持实测 `ports=4`，不要改为 15 |
| ROM / UUID 文本看似不同 | Vendor GUID、字节序、XNU UUID 派生 | 私下与本地配置核对，不重新随机生成身份 |

排障前保留原配置和日志。公开 Issue 时仅分享版本、设备 ID、脱敏错误片段和测试结论，不包含账号、密码、序列号、MLB、UUID、ROM、MAC、私网地址或完整 XML。
