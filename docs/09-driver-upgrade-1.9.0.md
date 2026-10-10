# 9. NullMoth 1.1.0 → 1.9.0 升级

记录日期：2026-10-11。适用范围是本仓库已有的 macOS 15.8.1 / RTX 3060 12GB VM。**1.9.0 已安装并完成下表验收，HEVC 硬编码像素仍失败。** 原先 1.1.0 的结果保留为历史基线，不能覆盖为新版结果。

上游 [v1.9.0 发布说明](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v1.9.0)说明：该包的 macOS 驱动组件与 1.7.0 相同。版本号变化不能单独证明修复了 HEVC 硬编码或第三方远控兼容问题。

## 先建立可恢复的完整冷备份

1. 通过 macOS 正常关机；在宿主机确认 `virsh domstate VM_NAME` 为 `shut off`，QEMU 已退出且没有进程持有该 VM 的磁盘。备份期间禁止 UI、自动启动或其他管理任务启动 VM。
2. 保存 `virsh dumpxml --inactive VM_NAME`，按 XML 和 `virsh domblklist VM_NAME --details` 逐一核对磁盘。备份系统盘、可写 EFI 盘、OVMF NVRAM，**以及所有附加可写磁盘，包括仍挂载的 delivery 盘**。有 backing chain 的 qcow2 还要保留完整依赖链，不能只复制顶层文件。
3. 保存实际使用的 EFI/config.plist、XML、BAR 配置和启动钩子；包括 flash 中的持久副本及相关 `/boot/config/go` 内容。记录现有包和组件摘要、系统版本、PCI BDF 与 BAR1 大小。真实身份和这些文件只放私有备份位置。
4. 每次新建唯一恢复点，不覆盖升级前或更早的恢复点。普通复制或 reflink 均可；不能把可写盘与备份做硬链接。逐项保留源路径与备份路径映射，防止相同文件名覆盖。
5. 在 VM 关闭时，对源 qcow2 和复制后的 qcow2 分别执行 `qemu-img check -f qcow2 /path/to/disk.qcow2`。raw 盘也必须备份并校验摘要，不能对 raw 套用 qcow2 格式检查。为全部备份文件生成 SHA256SUMS，执行 `sha256sum -c SHA256SUMS`，最后再确认 VM 仍关闭。

[checkpoint.sh](../scripts/unraid/checkpoint.sh)仅支持模板的两块盘和固定 NVRAM 路径。已有 VM 布局不同或带附加盘时，需要按实际 XML 补齐清单；脚本退出成功不能证明其他盘也已备份。更多恢复原则见[冷备份章节](07-backup-and-publishing.md)。

这次只升级驱动。保留原 VM UUID、网卡 MAC、SMBIOS 的 SSN / MLB / ROM、OpenCore 版本、CPU 配置及已验证的电源修复。**已有 VM 不运行公开配置工具的 `init`，不把脱敏模板覆盖到实际 EFI。**

## 验证升级包，再安装

使用上游 [1.9.0 tar.gz 资产](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.9.0/nullmoth-nvidia-1.9.0.tar.gz)，不要使用来源不明的重新打包文件。官方资产大小为 **269295455 字节**，SHA256 为：

```text
573546d77d6999ef4f5a808b036da39fa99b4856909f02c7b95adef017a240f2
```

在 macOS 的私有工作目录中执行；每一步失败都先处理，不能继续安装：

```bash
set -e
package=nullmoth-nvidia-1.9.0.tar.gz
curl -fL --retry 3 \
  https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.9.0/nullmoth-nvidia-1.9.0.tar.gz \
  -o "$package"
test "$(stat -f %z "$package")" -eq 269295455
printf '%s  %s\n' \
  573546d77d6999ef4f5a808b036da39fa99b4856909f02c7b95adef017a240f2 \
  "$package" | shasum -a 256 -c -
mkdir upgrade-1.9.0
tar -xzf "$package" -C upgrade-1.9.0
cd upgrade-1.9.0/pkgroot
test "$(grep -cE '^[[:xdigit:]]{64}[[:space:]]' SHA256SUMS)" -eq 53
shasum -a 256 -c SHA256SUMS
```

包内 **53 项 manifest 校验必须全部通过**，确认 install.sh 所在的 pkgroot 和脚本行为。网络受阻时优先使用实际下载机器可达的代理；代理在另一台机器时，不能直接把它的 `127.0.0.1` 填进 macOS。

保留已下载的 1.1.0 旧包、旧摘要及既有备份。升级前确认客户机 SSH、VNC 可以独立连接，并保存现有远控工具配置。[GlideBeam](https://github.com/dixtdf/GlideBeam)可用于日常远控；安装时显示服务可能中断，重启并登录后再验证恢复画面。驱动升级的救援入口仍需保留。

```bash
sudo ./install.sh
# 检查安装输出；有错误时不要执行下一条。
sudo shutdown -r now
```

按官方安装器处理系统授权提示，并保存安装器打印的 backup 路径及日志。不要为了升级额外清 NVRAM、改 SIP、重新分配 SMBIOS 或连续尝试未知 KC 重建命令。

可以从 1.1.0 直接覆盖安装，不先卸载。安装器先试建 AuxKC，备份旧组件后再写入，失败时尝试恢复；它不改 EFI 或既有 boot-args。`uninstall.sh` 会移除驱动并重建内核集合，**不是恢复旧版本的命令**；回到 1.1.0 使用完整冷备份。

本次使用 tar 包手动安装。1401 包装程序的 [NVENC 规则](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.9.0/app/Resources/nullmoth-rules.json)会对 Ampere 等架构设置软件编码回退，不能把它与本次手动路径的测试结果混用。tar 安装会替换 `nvmtl/nvrm610.conf`，自定义参数应先保存、逐项核对，不能盲目把旧配置整体盖回。

## 重启后的验收

NVRM、NVAccel、NVRMFB、NVRMAGDC 四个 kext 应安装在 `/Library/Extensions`，经系统辅助内核集合（AuxKC）加载；不要再注入 EFI/OC/Kexts。Metal 插件路径是 `/Library/GPUBundles/NVMTLDriver.bundle`。包版本应通过资产和组件摘要判定，不能只看 kext 的 CFBundleVersion。

先比较安装后的四个 kext 可执行文件与新包 SHA256SUMS 的对应条目；文件在磁盘上更新还不代表新二进制已经加载。结合 `kmutil showloaded`、安装日志及重启后的运行结果确认。下面只计算已安装二进制摘要，仍需与 manifest 比对：

```bash
for name in NVRM NVAccel NVRMFB NVRMAGDC; do
  bundle="/Library/Extensions/$name.kext"
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$bundle/Contents/Info.plist")
  shasum -a 256 "$bundle/Contents/MacOS/$exe"
done
kmutil showloaded | grep -Ei 'nullmoth|NVRM|NVAccel'
```

随后切回本教程仓库根目录，运行仓库中的验收脚本；这些路径不在驱动的 `pkgroot` 中：

```bash
bash scripts/macos/verify-system.sh
bash scripts/macos/run-native-tests.sh
```

验收项目和边界见[原生测试章节](06-validation-and-troubleshooting.md)。至少记录：

- Metal 的 NVIDIA 设备枚举、缓冲区复制、计算、渲染像素三项结果，不能只看“Metal 3”。
- H.264 与 HEVC 各路径的 API 状态、实际硬编 / 硬解标记、帧数和像素 MAE。HEVC API 成功但像素错误仍算失败；视频测试进程退出 0 只表示产生报告。
- SSH / VNC 端口监听与实际连接，GlideBeam 登录后画面恢复；显示器输出和基本输入是否正常。
- 1 个 AppleSMC / 0 个 VirtualSMC IOService，BAR1 实际大小保持 8GiB。保留 QEMU AppleSMC 和既有 `-vsmccomp` 修复。
- 客户机正常重启后 SSH 恢复；正常关机后宿主机显示 `shut off` 且 QEMU 退出。不能用强制销毁 VM 代替验收。

## 回滚与本次记录

无法启动、驱动异常或远程入口丢失时，优先恢复**同一个完整冷备份**的系统盘、EFI、NVRAM、XML及相关附加盘和 BAR 钩子，避免混用不同时间点。停止 VM 并核实文件占用，校验备份摘要及 qcow2 后再恢复。替换前另存失败状态和日志，所有目标路径逐一核对。能进入 macOS 时也可按官方卸载说明处理安装器备份，但这不能替代完整冷备份。

| 项目 | 2026-10-11 本次结果 |
| --- | --- |
| 1.1.0 升级前冷备份 | 3 块盘、NVRAM、XML、宿主机钩子 / 启动脚本及固件已保存；8 项 SHA 清单全部校验通过 |
| 1.9.0 升级后冷备份 | 同范围另建恢复点；源及备份 qcow2 检查通过，8 项 SHA 清单完整复核全部通过 |
| 资产 SHA256 / 53 项 manifest | 全部通过，安装成功 |
| 四个 kext 二进制与加载 | SHA 与新包对应项一致，四个 kext 已加载 |
| 系统与显卡 | 10 核 / 20 线程、16GiB、RTX 3060 12GB / Metal 3，1920×1080@60 在线 |
| EFI / XML | EFI 身份未改，XML 语义未改 |
| Metal 缓冲区 / 计算 / 渲染 | 三项通过；仍为小规模测试 |
| H.264 硬编码 → 硬解 / 软解 | 1280×720、30 帧，像素验收通过，硬件标记已核对 |
| HEVC 硬编码 | 输出像素失败，与 1.1.0 的失败结论相同 |
| HEVC 软件编码 → 硬解 | 1280×720、30 帧，像素验收通过，硬件解码标记已核对 |
| SSH / VNC | 重启后 SSH 恢复；VNC 认证成功并取得真实 1920×1080 登录画面 |
| GlideBeam | 已登录桌面的 GlideBeam 远控尚未复测 |
| BAR1 / AppleSMC | BAR1 8GiB；完整类名统计为 1 AppleSMC / 0 VirtualSMC |
| 重启 / 正常关机 | warm reboot 成功；`sudo shutdown` 正常使 QEMU 退出，宿主机状态为 `shut off` |

这些结果不代表 4K、HDR、长时间稳定性、所有编码 profile 或所有第三方应用通过。升级后恢复点只有完整 SHA 清单复核通过才视为校验完成；原升级前恢复点继续保留。

公开结果只保留版本、摘要、测试范围和结论，不上传真实 EFI / XML、完整系统日志、私有备份路径、凭据或机器身份。

统计 SMC 时匹配完整类名：`<class AppleSMC,`。`AppleSMCClient` 是客户端对象，不能算作额外的 AppleSMC 服务。
