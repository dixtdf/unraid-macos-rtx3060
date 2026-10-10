# 10. NullMoth 1.10.0 兼容性审查（未实机安装）

**RTX 3060 存在功能退步：1.10.0 不再注册 NullMoth 的 H.264 / HEVC 硬编码器，现有 GlideBeam 生产路径没有软件回退。按源码审查，升级后会失去现有 GlideBeam 画面；参考机仍运行已验证的 1.9.0。**

记录日期：2026-10-11。[v1.10.0 驱动源码](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.10.0/plugin/NVMTLDevice.m)的 `nvmtl_video_is_blackwell` 判断使非 Blackwell 显卡跳过编码器注册，tar 安装也受影响。

[GlideBeam 生产代码](https://github.com/dixtdf/GlideBeam/blob/10a70207d29a282f605798fc3640c404f6784a2d/apps/macos-host/main.mm#L153)强制硬件编码，拒绝软件会话；初始化失败就停止采集。仓库 probes 的软件测试不属于生产回退。上述兼容性结论是源码推断，1.10.0 尚未实机安装。

备份与回滚沿用[上一章](09-driver-upgrade-1.9.0.md)，保持 EFI、OpenCore 和身份。1.9.0 的 H.264 30 帧像素通过，**HEVC 硬编码像素仍失败**。

## 上游变化与安装路径

[v1.10.0 发布说明](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v1.10.0)列出 OpenCL、managed GPU memory、纹理可写属性、RTX 50 以前显卡的 H.264 解码、显示模式及鼠标旧帧修复。这些尚未在本机逐项验收。

如果升级，使用官方 tar 的 `install.sh`；安装 / 卸载脚本与 1.9.0 相同，不改 EFI。1401 Mac 应用会启用 Lilu / AMFIPass，此处不走该流程。

## 先保存已验证的 1.9.0

正常关机并确认 QEMU 退出、磁盘无占用后冷备，覆盖所有可写盘和依赖链（包括 delivery 盘）、EFI、NVRAM、XML、BAR 配置与钩子。完成 qcow2 和 SHA256 校验，保留旧恢复点和包。

## 校验并安装 1.10.0

官方 [tar.gz 资产](https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.10.0/nullmoth-nvidia-1.10.0.tar.gz)大小为 **269301698 字节**，SHA256 为：

```text
47f9cd65201409d48952eb84d122c32e8a1867045d8d8f61e890ad559324ccb5
```

以下仅适用于接受编码变化、改用 VNC 或已实现并验证软件回退的场景；需要现有 GlideBeam 时保留 1.9.0。任一步失败就停止：

```bash
set -e
package=nullmoth-nvidia-1.10.0.tar.gz
curl -fL --retry 3 \
  https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.10.0/nullmoth-nvidia-1.10.0.tar.gz \
  -o "$package"
test "$(stat -f %z "$package")" -eq 269301698
printf '%s  %s\n' \
  47f9cd65201409d48952eb84d122c32e8a1867045d8d8f61e890ad559324ccb5 \
  "$package" | shasum -a 256 -c -
mkdir upgrade-1.10.0
tar -xzf "$package" -C upgrade-1.10.0
cd upgrade-1.10.0/pkgroot
shasum -a 256 -c SHA256SUMS
sudo ./install.sh
# 检查安装输出；有错误时不要执行下一条。
sudo shutdown -r now
```

保留 SSH / VNC 救援入口与安装日志，下载受阻时优先使用可达代理。

## 验收与回滚

按[上一章清单](09-driver-upgrade-1.9.0.md#重启后的验收)复核组件、Metal、视频、远控、BAR1、SMC 和电源。保留 H.264 30 帧对比，不能把软件回退算作硬编成功。

OpenCL、内存与纹理新功能需要专项测试。故障时优先恢复完整 1.9.0 冷备份，另存失败状态，不混用不同恢复点。

| 项目 | 本次 1.10.0 结果 |
| --- | --- |
| 1.9.0 完整冷备份与校验 | 已另建冷备，源及备份 qcow2 检查通过，8 项 SHA 清单完整复核全部通过 |
| 下载资产 / manifest 校验 | 宿主机已下载，资产 SHA 一致，54 项 manifest 全部通过 |
| 已安装组件 / Metal 三项 | 未安装，未测试 |
| H.264 / HEVC 像素与硬件标记 | 未安装，未测试 |
| VNC / GlideBeam / 显示与输入 | 未安装，未测试 |
| BAR1 / AppleSMC / 重启 / 关机 | 未安装，未测试 |
| OpenCL / 内存 / 纹理专项 | 未安装，未测试 |

只有实际验证后才更新结论和恢复点；不公开私有路径、身份、凭据或完整日志。
