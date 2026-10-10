# 3. OpenCore 与独立身份

本仓库的 plist 是 OpenCore **1.0.5** 格式，完整 EFI 树来自 LongQT v0.7。不要把它交给其他版本的 OpenCore，也不要只下载 plist 后缺少引用的驱动 / kext / ACPI 文件。EFI 中保留 Lilu、VirtualSMC、WhateverGreen、VoodooPS2、AppleMCEReporterDisabler，以及 `SSDT-EC.aml`、`SSDT-USBX.aml`。没有添加物理主板专用 USB 映射或更多 10900K SSDT。

## 生成身份一次，以后保持

使用 [OpenCore 1.0.5 官方 macserial](https://github.com/acidanthera/OpenCorePkg/tree/1.0.5/Utilities/macserial)，在其支持的平台运行：

```bash
macserial -g -m iMacPro1,1 -n 1
```

取得同一行的 **SystemSerialNumber / MLB 配对**。将其作为本地参数，不复制本教程作者或其他机器的序列号。本次实际身份也来自官方 macserial；没有用 Apple 覆盖查询或 Apple ID 登录作为验收，因此不承诺 iMessage、FaceTime 或 Apple 激活状态。

在仓库目录执行，使用自己的 PCI BDF、序列号和 MLB：

```powershell
py -3 tools/configure.py init --serial YOUR_SERIAL --mlb YOUR_MLB `
  --gpu YOUR_GPU_BDF --audio YOUR_AUDIO_BDF --vm macos15 `
  --root /mnt/user/domains/macos15
```

`init` 将生成独立 UUID 和 MAC 并保存到 `local/settings.json`；已存在时拒绝覆盖。之后只编辑这个文件并重新 `build`，不要再初始化身份。UUID 用作 libvirt VM UUID 与 `Generic.SystemUUID`，ROM 自动取网卡 MAC 的 6 个字节，因此各安装阶段保持一致。

`local/settings.json` 中填入自行取得的 **Apple SMC OSK**，核实 OVMF 文件路径和网桥；OSK 不随仓库分发，也不要放在公开命令行、日志或 Git 提交中。字段应是本地 64 字节 ASCII 字符串。系统账户 / VNC / SSH 密码不需要放进这个文件。

```powershell
py -3 tools/configure.py build --stage install --domain
py -3 tools/configure.py build --stage gpu --domain
```

产物分别位于 `local/install/` 和 `local/gpu/`。若只需要 plist，可省略 `--domain`，这时不需要 OSK。重复生成会拒绝覆盖；在保留备份后才加 `--force`。Linux / macOS 用 `python3` 替换 `py -3`。

## 两个阶段的差别

| 设置 | install | gpu |
| --- | --- | --- |
| 显卡 | Cirrus 虚拟显示器 / Unraid VNC | GPU + 音频直通，`video type=none` |
| Recovery / Installer 盘 | 附加 | 已移除 |
| SIP 数据 | `00000000` | `430A0000`，特定允许位组合 |
| `IONDRVSupport` Block | Disabled | Enabled，Strategy=Exclude |
| boot-args | 调试信息与 `-vsmccomp` | 再加入 NullMoth framebuffer / accelerator 与 AMFI 参数 |
| SecureBootModel | Disabled | Disabled |

最终 GPU 参数：

```text
-v keepsyms=1 debug=0x100 nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 -vsmccomp
```

`csr-active-config` 必须是 **Data**，原始字节 `43 0A 00 00`，数值为 `0x0A43`；不要当成字符串写入，也不要称为“全部 SIP 关闭”。驱动阶段包含 AMFI 放宽参数，是这套实验驱动配置的一部分。安装与驱动配置都保留 `-vsmccomp`，让 VirtualSMC 使用 QEMU 已有的 AppleSMC。

两阶段均保持：

- `Booter.Quirks.ProvideCustomSlide=true`：实测解决 `EB.MM.AKMR` / `EB.M.BAPr2 Err(0xE)` 的 KASLR 可用内存问题。
- `Kernel.Quirks.ProvideCurrentCpuInfo=true`；`Generic.ProcessorType=4105 (0x1009)`，对应 Comet Lake i9。
- `Booter.ResizeAppleGpuBars=-1`、`UEFI.ResizeGpuBars=-1`：BAR 由宿主机处理。
- `PlatformInfo.Automatic=true`，UpdateDataHub / UpdateNVRAM / UpdateSMBIOS=true，UpdateSMBIOSMode=Create，UseRawUuidEncoding=false。
- `DeviceProperties.Add={}`：不保留猜测的 iGPU、音频或网卡 PCI 路径。

本次尝试 RestrictEvents 与其他 ProcessorType 并没有修好 ES 处理器名称，有一次反而显示为 16-Core Xeon W；最终已移除这些试验。不要再次加入 `rev*` 参数来追求名称。

## 验证并写入实际引导盘

每次修改后必须使用**官方 ocvalidate 1.0.5**验证。构建 EFI 脚本也会执行这个检查。本次导出的公开模板在身份字段留空时只用于生成，真正用于引导的是 `local/` 中已填写的配置。

```bash
/path/to/ocvalidate /path/to/config.plist
```

在 VM 停止时挂载其专用 EFI raw 的 ESP 并替换 `EFI/OC/config.plist`，或者在 macOS 中用 `diskutil list` 确认真正启动用的 EFI 后挂载再替换。先备份旧文件，复制后 `cmp`，同步并卸载。不要修改别的硬盘 EFI，不要只改了仓库里的文件却忘记实际引导盘。

模板会在 NVRAM 的 Add / Delete 中同步更新 boot-args 与 SIP 数据。不要习惯性 Reset NVRAM；它会丢掉启动顺序和其他变量。若实际参数仍陈旧，再针对 NVRAM 排查，并先保存变量文件。

## 身份与 SMC 的实际校验

在自己的 Mac 上私下比较 `ioreg` / `nvram`，不要上传整份输出。OpenCore 将 SSN、MLB、ROM 写入 Apple vendor GUID `4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14`；默认 `nvram -xp` 可能看不到这些命名空间变量，需按 `GUID:变量名` 查询 `SSN / HW_SSN / MLB / HW_MLB / ROM / HW_ROM`。

`IOPlatformUUID` 由 XNU 通过 SMBIOS UUID 派生，并非一定等于 XML 的 UUID 字符串。UseRawUuidEncoding=false 还会影响字节序。不要仅凭两个文本不相同就重新生成 UUID。

参考：[OpenCore 身份更新代码](https://github.com/acidanthera/OpenCorePkg/blob/1.0.5/Library/OcMainLib/OpenCorePlatform.c)、[XNU 的 IOPlatformUUID 派生](https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.140.69/iokit/Kernel/IOPlatformExpert.cpp)、[OpenCore 1.0.5 配置文档](https://github.com/acidanthera/OpenCorePkg/blob/1.0.5/Docs/Configuration.tex)。
