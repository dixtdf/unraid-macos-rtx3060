# 13. Apple ID 登录排障与 VM sysctl 修补

2026-10-11，本机在保持原有身份的情况下完成修补，用户随后确认**系统设置中的 Apple 账户登录成功**。App Store 独立登录、iMessage、FaceTime 尚未测试。这个结果适用于本次机器和系统版本，不能将相同错误码或 `kern.hv_vmm_present=1` 单独视为所有登录失败的根因。

本章记录实际处理顺序和已确认的副作用，供维护既有 VM 时参考。[本次脱敏结果](../results/observed-2026-10-11-apple-id.json)是公开验收入口。仓库生成模板没有默认加入本修补；复现前需要核对自己的系统、目标内核、身份和回滚条件。

## 故障与验证范围

| 项目 | 本次事实 |
| --- | --- |
| 系统与引导 | macOS 15.8.1 / 24H32，Darwin 24，OpenCore 1.0.5 |
| 设备与驱动 | iMacPro1,1，RTX 3060 12 GB，NullMoth 1.9.0 |
| 用户报告 | 系统设置和 App Store 均提示“验证失败，发生未知错误” |
| 登录日志 | ADI `-45061`、Anisette `-8001` / `-8008`、设备证明 `baa -10000`、服务器 `-22410` |
| 修补前身份 | libvirt / Generic UUID 一致；SSN、MLB、ROM 与运行时对应；内建 en0 正确；运行时 UUID 派生正确 |
| 实际改动 | 仅追加两个 Darwin 24 范围的 `Kernel.Patch`；保留 CPU VMM 特征、VM XML、身份及其余 EFI 配置 |
| 修补后身份 | 原配置身份、运行时 UUID 和六项身份 NVRAM 值均保持 |
| 用户验收 | 系统设置登录成功；其他 Apple 服务仍待独立验收 |

日志用于定位失败发生的阶段。账户状态、网络、系统时间、Apple 服务状态或其他配置也可能导致登录失败，不能根据错误码直接执行修补或重新生成序列号。先按 [Apple 官方登录排障](https://support.apple.com/en-us/118446)检查基本条件，再针对这台 VM 的证据决定下一步。

## 先排查身份，不重置身份

既有 VM 的身份检查应是比较，不是重新运行 `configure.py init`。按 [OpenCore 与独立身份](03-opencore-and-identity.md)私下核对：

1. 当前实际引导 EFI 的 `PlatformInfo.Generic`，以及 libvirt UUID、MAC、ROM 是否仍是首次生成的值。
2. SSN / HW_SSN、MLB / HW_MLB、ROM / HW_ROM 六项 NVRAM 值是否与配置对应。默认 `nvram -xp` 不一定列出 Apple vendor 命名空间，按该章说明查询。
3. en0 是否是预期网卡且具有内建属性；只检查实际设备路径，不添加猜测的 `DeviceProperties`。
4. `IOPlatformUUID` 是否符合当前 XNU 的派生规则，不能要求其文本必须等于 `Generic.SystemUUID`。

本机 Generic 和 libvirt UUID 为相同的 version 4，运行时 `IOPlatformUUID` 为 version 5。根据 [XNU IOPlatformExpert 的实现](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/iokit/Kernel/IOPlatformExpert.cpp)，后者由固定命名空间与 `/efi/platform/system-id` 的字节通过 SHA-1 派生。本次私下计算结果与运行时值一致，差异属于预期行为，没有更换身份。

只读采集可包括以下命令；日志及身份输出保留在本地，不整份提交到仓库：

```bash
sw_vers
uname -r
sysctl kern.hv_vmm_present
pmset -g custom
log show --last 10m --style compact --predicate 'process == "akd"'
```

记录一次用户尝试登录前后的时间范围，避免用数小时旧日志推断本轮结果。不要以清空 NVRAM、删除钥匙串、清除账户数据库或反复换序列号作为默认排障步骤。

## 为什么保留 CPU 的 VMM 标志

直接在 libvirt 的 host-passthrough CPU 中禁用 `hypervisor` 特征会改变内核和 OpenCore 对虚拟 CPU 的识别。它不等同于只改变某一个 sysctl 的返回值。

[XNU cpuid.c](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/osfmk/i386/cpuid.c)根据 CPU VMM 位获取 KVM 提供的虚拟机与频率信息；[tsc.c](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/osfmk/i386/tsc.c)使用这些信息选择时钟路径。[OpenCore 1.0.5 OcCpuLib](https://github.com/acidanthera/OpenCorePkg/blob/1.0.5/Library/OcCpuLib/OcCpuLib.c)也用 Hypervisor 状态决定部分 MSR 读取和频率处理。改变这个位可能触发不同的 TSC / MSR 启动路径，需要另行验证。

因此本次保留 CPU VMM 位，采用已有项目使用的两项内核字符串修补。它缩小了改动范围，仍有全局 sysctl 副作用，不能称为对虚拟机完全无影响。

## 固定来源和参数

字节来自 [Docker-OSX 固定提交的修补定义](https://github.com/sickcodes/Docker-OSX/blob/b282993a4a3bf6cb379cbcf406cc81c8d7582fe2/scripts/apply_appleid_kernelpatch.py)，提交为 `b282993a4a3bf6cb379cbcf406cc81c8d7582fe2`；相关采用记录见 [OSX-KVM PR #264](https://github.com/kholia/OSX-KVM/pull/264)。本次只沿用字节定义，没有在服务器直接运行下载的上游脚本。

这两个修补交换 sysctl 名称所在的字符串：

| 项 | Find，`\0` 表示 NUL 字节 | Replace |
| --- | --- | --- |
| 1 | `hibernatehidready\0hibernatecount\0` | `hibernatehidready\0hv_vmm_present\0` |
| 2 | `boot session UUID\0hv_vmm_present\0` | `boot session UUID\0hibernatecount\0` |

每个 Find / Replace 均为 **33 字节**，必须成对启用。它没有将原来的 VMM 检测函数改成永久返回零：修补后读取 `kern.hv_vmm_present` 实际得到休眠计数，读取 `kern.hibernatecount` 则得到原来的 VMM 状态。

下面仅为 `Kernel.Patch` 参数示例；保留已有数组中的其他项目。Find / Replace / Mask / ReplaceMask 是 plist 的 **Data** 类型，不能把 Base64 文本写成 String。

| 两项共有字段 | 值 |
| --- | --- |
| Arch / Identifier | `x86_64` / `kernel` |
| Base | 空 String |
| Count / Skip / Limit | `1` / `0` / `0` |
| Enabled | `true`，仅在预检通过并决定应用后启用 |
| Mask / ReplaceMask | 空 Data |
| MinKernel / MaxKernel | `24.0.0` / `24.99.99` |

两项 Data 的 Base64 编码：

```text
PART 1 Find:    aGliZXJuYXRlaGlkcmVhZHkAaGliZXJuYXRlY291bnQA
PART 1 Replace: aGliZXJuYXRlaGlkcmVhZHkAaHZfdm1tX3ByZXNlbnQA
PART 2 Find:    Ym9vdCBzZXNzaW9uIFVVSUQAaHZfdm1tX3ByZXNlbnQA
PART 2 Replace: Ym9vdCBzZXNzaW9uIFVVSUQAaGliZXJuYXRlY291bnQA
```

上游原始定义的 MinKernel 分别为 `20.4.0`、`22.0.0`，MaxKernel 为空。本次将两项都限制为 Darwin 24，并调整 Comment 说明实际用途。**本次实测只有 24H32**；设置 Darwin 24 范围不代表该范围内的所有系统都已验证，更不适用于 Darwin 25 或更新内核。

本次检查当前 `/System/Library/KernelCollections/BootKernelExtensions.kc`，两个 Find 各命中一次。自己的内核需要重新检查；`ocvalidate` 通过只证明配置符合对应 OpenCore 格式，不能证明目标字节匹配或登录必定成功。

## 最小操作顺序

1. 完成上述只读检查，记录系统版本、实际 EFI、CPU VMM 位、登录错误与原身份比较结果。关机前采集当前 `BootKernelExtensions.kc`，记录两个 Find 的命中次数，供离线修改时核对。确认有可用的 SSH / macOS VNC 等恢复入口。
2. 在 macOS 内正常关机，等待 libvirt 报告 VM 为 `shut off`、QEMU 退出后，做完整冷备。按 [备份与发布](07-backup-and-publishing.md)保留实际磁盘、EFI、NVRAM、域定义及关联启动配置；比较源文件与副本，核对 SHA-256，并检查源和副本 qcow2。不要复制运行中的系统盘作为这一步的完整备份。
3. 从实际 EFI 提取当前 plist，在私有副本中只追加上述两项，排除重复条目。结构化比较确认其余配置未改，检查当前内核目标。用官方 **ocvalidate 1.0.5** 验证候选文件。
4. 保持 VM 停止并锁定维护操作，重新比较 EFI / NVRAM / 域定义与备份。确认真正的 ESP 后仅写入实际 `EFI/OC/config.plist`；分区偏移或设备路径需在本机确认，不照搬别人的数值。写后回读、逐字节比较，再运行 `ocvalidate`，同步并卸载。
5. 启动 VM，先检查系统、身份、sysctl、休眠、电源和远控回归，再让用户本人在系统设置尝试登录。密码、验证码和 Apple 账户信息无需交给 AI，也不要写入记录。

本次完成了约 51G 的冷备，8 个文件的 SHA-256、源 / 副本比较及源 / 副本 qcow2 检查均通过。候选文件在官方 Windows 与 Linux `ocvalidate 1.0.5` 下通过，实际写入后的回读也通过。这是本次执行证据，不是其他机器可以跳过备份与预检的理由。

## 已确认的副作用

### 休眠计数与软件更新

保持 `hibernatemode=0`、`sleep=0`；本机这两项已验证。必要时先保存现有 `pmset` 配置，再按本机使用目的设置：

```bash
sudo pmset -a hibernatemode 0 sleep 0
```

[XNU 的休眠实现](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/iokit/Kernel/IOHibernateIO.cpp)会在休眠恢复时更新计数。由于本修补交换名称，`kern.hv_vmm_present=0` 依赖实际休眠计数为零，不保证经历休眠后仍为零；本机修补后的 `kern.hibernatecount=1` 表示原来的 VMM 检测值，不能据此判断曾经休眠。

全局 sysctl 映射还可能改变其他识别 VM 的软件及 macOS 更新行为。本次没有执行系统更新验证；以后升级系统前需重新检查字节匹配、OpenCore、休眠和这些副作用。

### AppleQEMUGuestAgent 不再运行

本机 AppleQEMUGuestAgent 的 launchd plist 没有 `RequireVirtualMachine` 条件。只读检查实际二进制确认，它调用 `sysctlbyname("kern.hv_vmm_present")` 并要求结果为 `1`；修补后结果为 `0`，因此记录 `Invalid guest agent environment` 并以 exit 1 退出，libvirt `guest-ping` 报未连接。

旧日志已有缺少 `apple-guest-agent-port` 等设备树属性的报错，但本次新增的环境检查退出与 sysctl 修补直接相关。没有记录修补前 `guest-ping` 成功的基线，不能宣称破坏了此前已验证的连接；**当前代理不可用和退出原因已确认**。不要把 XML 中存在 virtio 通道当成代理实际可用。

这次没有修改或启动代理，也没有通过更改 CPU VMM 位解决这个副作用。依赖 QEMU guest agent 的宿主机功能需要另行评估；本机已通过 macOS 内正常重启 / 关机验证电源路径，二者的结论不能互相替代。

## 重启后的实际回归

| 检查 | 本次结果与边界 |
| --- | --- |
| sysctl / CPU | `kern.hv_vmm_present=0`，交换后的 `kern.hibernatecount=1`；真实 CPU VMM 位保留 |
| 身份 | 原配置、六项身份 NVRAM 与运行时 UUID 均保持；派生校验匹配 |
| 正常热重启 | 收到 libvirt reboot 事件，macOS 重新启动并恢复服务 |
| 正常关机 | 收到 libvirt shutdown 事件，QEMU 日志 reason 为 `shutdown`，没有用强制 destroy 代替 |
| 最终冷启动 | 原系统盘正常启动，RTX 3060 / 1.9.0 与远控服务恢复 |
| GlideBeam codec 自测 | 30 帧生产编码器、强制 IDR 和软件解码后的像素 / 位置校验通过；编码器为 `com.nvmtl.videoencoder.avc.nvenc`，硬件 H.264 |
| 热重启后 QUIC | 12 秒收到 299 条视频记录，硬件编码模式，编码错误 0 |
| 最终冷启动后 QUIC | 12 秒收到 300 条视频记录，硬件编码模式，编码错误 0 |
| QEMU guest agent | 当前退出，`guest-ping` 不可用 |

两次 QUIC 测试只读取状态与数据记录，没有发送输入事件，也没有 Windows 视频解码或呈现。因此 299 / 300 条记录**不等于 Windows 实际呈现帧数或 FPS**，不能据此承诺端到端延迟、持续远控稳定性或鼠标键盘验收。30 帧自测使用软件解码检查 H.264 编码输出，也不代表 GPU 硬件解码通过。

以后复测至少保留 sysctl / CPU、身份、休眠、正常 reboot / shutdown、GPU / 编码器和代理状态这几项；Apple 服务则逐项由用户实际登录确认。

## 只回退本次 EFI 改动

本次回滚目标是移除新增两项修补并恢复原 EFI 配置。先在 macOS 内正常关机、确认 VM 停止，保存当前 EFI，再检查当前配置是否仍为已知候选版本；若已有后续改动，先比较并合并，不能盲目覆盖。

恢复备份中的原 `EFI/OC/config.plist`，回读逐字节比较并用 `ocvalidate 1.0.5` 验证，随后启动并重做 sysctl、身份、电源和远控检查。若写入过程失败，可在确认 VM 停止时恢复此前完整 EFI 镜像，并核对备份散列。

**不要为了撤销这两个修补而恢复旧系统盘。**本次只修改 EFI 配置，没有替换系统盘或修改身份、VM XML、NVRAM；回退老系统盘会丢失修补后的用户数据。代理能否重新连接、用户是否仍保持登录也需实际检查，不能只依据 EFI 恢复成功宣布全部恢复。

## 本地证据与发布边界

本机私有交接文件位于 `local/tools/appleid-20261011/`，不随仓库分发；公开读者应以[脱敏结果](../results/observed-2026-10-11-apple-id.json)为入口：

- `prepared-fix.json`：固定来源、字节、目标命中次数、候选差异及校验。
- `final-handoff.json`：冷备检查、最终配置、身份保持、电源事件、codec / QUIC 回归和回滚条件。
- `user-login-confirmation.json`：用户对系统设置登录成功的明确反馈；App Store 独立登录未验收。

这些原始文件只保留在本地。本章仅发布脱敏结论、补丁字节与参数示例，不发布真实 IP、UUID、MAC、SSN、MLB、OSK、填写后的 plist / XML、原始身份和登录日志，也不上传上游 EFI 或驱动二进制。
