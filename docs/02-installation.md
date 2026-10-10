# 2. 安装 macOS 15.8.1（24H32）

先完成[身份与配置生成](03-opencore-and-identity.md)，取得 `local/install/config.plist` 和 `domain.xml`。安装时保留 Unraid 的虚拟显卡和 VNC，不启用 NVIDIA 驱动。始终使用同一套身份和同一个可写 EFI 引导盘。

## A. 已有一台可用的 Mac

按 [Apple 官方说明](https://support.apple.com/102662)取得指定版本完整安装器，先查看仍可下载的版本：

```bash
softwareupdate --list-full-installers
softwareupdate --fetch-full-installer --full-installer-version 15.8.1
```

在 Mac 上把专用空白安装盘格式化为 GUID / Mac OS Extended，命名 `Installer`，然后执行：

```bash
sudo '/Applications/Install macOS Sequoia.app/Contents/Resources/createinstallmedia' \
  --volume /Volumes/Installer --nointeraction
```

此命令会抹掉目标卷。务必确认是专用安装盘。若保存为给 VM 使用的磁盘镜像，保留整盘分区表，转换成 raw 后作为 SATA 安装盘挂载。不要把一个普通目录或仅包含 pkg 的 ISO 当成可启动安装介质。

## B. Windows + Unraid：本次实际采用的路径

本次从 Apple CDN 取得完整包，从同一个包重建 15.8.1 的恢复系统，再在 Recovery 内制作完整安装盘。这样可以确认最终安装版本，而不是让在线 Recovery 自动选择最新版本。需要 Windows 版 7-Zip、Python、Linux 的 `dmg2img`，以及至少约 70GB 临时空间。

### 下载并校验

在仓库目录打开 PowerShell。下面的 Apple URL 对应本次实测产品 `142-27431`；若已失效，从 Apple 官方渠道重新取得指定版本，不能用其他文件替换后绕过校验。

```powershell
New-Item -ItemType Directory -Force media | Out-Null
$url = 'https://swcdn.apple.com/content/downloads/07/04/142-27431-A_VX0FXASAKC/m7trj81qnvp94e9nzr06e7qi9lqey7cwmu/InstallAssistant.pkg'
& "$env:WINDIR\System32\curl.exe" -fL --retry 6 --retry-all-errors `
  --proxy http://127.0.0.1:10808 -o media/InstallAssistant-15.8.1-24H32.pkg $url
py -3 tools/apple_media.py verify package media/InstallAssistant-15.8.1-24H32.pkg
```

代理是本机示例，按自己的网络调整。不要使用 `-k` 关闭 HTTPS 校验。下载中断后可使用 curl `-C -`，但完成后仍须校验整个文件。

实测包大小 `15664523626` 字节，SHA256 为 `e4532e3337431292a7f227fcde7eb57f7b907547e2a26b43d3aab5a3f6e44781`。Apple 当时目录中的 SHA1 与最终包不一致；本次另外验证了 HTTPS 下载的完整性分块、XAR TOC 签名及 Apple 证书链、各 XAR 文件摘要。这里的工具只比对**固定实测文件的大小 / SHA256**，没有实现那些签名检查；遇到不同文件应停止并重新核实来源。

### 提取 Payload 与精确 Recovery

这个 InstallAssistant 是 XAR / DMG 混合容器，7-Zip 必须明确指定类型。以下每个输出目录应为空；不要接受覆盖已有文件。

```powershell
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$pkg = 'media/InstallAssistant-15.8.1-24H32.pkg'
& $sevenZip e -txar $pkg Payload -omedia/payload
py -3 tools/apple_media.py pbzx media/payload/Payload media/Payload.cpio
& $sevenZip x -tdmg $pkg 5.hfs -omedia/sharedsupport
& $sevenZip e -thfs media/sharedsupport/5.hfs `
  'Shared Support/com_apple_MobileAsset_MacSoftwareUpdate/a30f5f5e5659a0760382124bee535d7ac33cb51f.zip' `
  -omedia/asset
& $sevenZip e media/asset/a30f5f5e5659a0760382124bee535d7ac33cb51f.zip `
  '*x86_64BaseSystem.dmg' -r -omedia/recovery
py -3 tools/apple_media.py bx media/recovery/x86_64BaseSystem.dmg media/BaseSystem-15.8.1-24H32.dmg
py -3 tools/apple_media.py verify recovery media/BaseSystem-15.8.1-24H32.dmg
```

这里的 `x86_64BaseSystem.dmg` 外层是 `BXDIFF50`。**只有 flags=0、control size=0 的这个完整载荷可以这样重建**；其他版本若是实际增量补丁，需要对应源镜像。工具会拒绝不支持的格式。

本次重建的 BaseSystem：大小 `1334686716` 字节，SHA256 `fb7db37cb6501690f63f71b80c6e940130aeca2a30dfcc781d335aa452751343`。原安装过程中也验证过 Apple 签名 chunklist 的 128 个分块；导出工具以固定 SHA256 验证相同文件。

在有 `dmg2img` 的 Linux / WSL 环境转换，再把输出上传到 Unraid 的 VM 专用目录：

```bash
dmg2img BaseSystem-15.8.1-24H32.dmg Recovery.img
```

在 Recovery 内确认 `/System/Library/CoreServices/SystemVersion.plist` 的 `ProductVersion=15.8.1`、`ProductBuildVersion=24H32`。从 OpenCore 官方 `Utilities/macrecovery` 下载的在线 Recovery 可作为救援入口，但其返回版本会变化，不作为本仓库的精确版本保证。

### 建立可写 EFI、系统盘和传递盘

下载 [LongQT OpenCore ISO v0.7](https://github.com/LongQT-sea/OpenCore-ISO/releases/tag/v0.7) 的 `LongQT-OpenCore-v0.7.iso`，以及 [OpenCore 1.0.5 RELEASE](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.5) 中适用于 Linux 的 `ocvalidate`。将它们和生成的 install 配置上传到 Unraid 的专用目录，然后执行：

```bash
VMROOT=/mnt/user/domains/macos15
mkdir -p "$VMROOT/efi" "$VMROOT/media" "$VMROOT/nvram"
bash scripts/unraid/build-efi-image.sh \
  "$VMROOT/efi/LongQT-OpenCore-v0.7.iso" \
  "$VMROOT/efi/config.install.plist" /path/to/ocvalidate \
  "$VMROOT/efi/OpenCore.raw"
test ! -e "$VMROOT/vdisk1.qcow2" && qemu-img create -f qcow2 "$VMROOT/vdisk1.qcow2" 160G
test ! -e "$VMROOT/media/Installer.raw" && qemu-img create -f raw "$VMROOT/media/Installer.raw" 32G
bash scripts/unraid/build-delivery-image.sh \
  "$VMROOT/media/InstallAssistant-15.8.1-24H32.pkg" \
  "$VMROOT/media/Payload.cpio" "$VMROOT/media/Delivery.raw"
```

脚本仅构建**新文件**，不会修改现有磁盘。Delivery 是 exFAT，因 pkg 超过 FAT32 的单文件限制。`mkfs.exfat` 不存在时，先在有相应工具的 Linux 环境构建，不要改成 FAT32。

将 `Recovery.img` 放到模板要求的路径，检查并编辑 `local/install/domain.xml`。若采用 Delivery 路径，在 `<devices>` 增加以下 SATA 盘（模板中的 unit 3 未占用）：

```xml
<disk type="file" device="disk">
  <driver name="qemu" type="raw" cache="none"/>
  <source file="YOUR_VM_ROOT/media/Delivery.raw"/>
  <target dev="hdd" bus="sata"/>
  <address type="drive" controller="0" bus="0" target="0" unit="3"/>
</disk>
```

使用实际绝对路径替换 `YOUR_VM_ROOT`。确认 OVMF 路径、网桥、磁盘均存在。在 VM 停止时通过 Unraid XML 编辑或 `virsh define /path/to/domain.xml` 导入。直接 `virsh define` 后，确认 Unraid UI 中显示对应配置，不要再用表单保存覆盖自定义 XML。模板的 VNC 只监听宿主机 loopback，通过 SSH 隧道访问；使用 Unraid 自带 noVNC 时，由管理界面设置适合其代理的监听地址和认证，不要直接向公网开放。

### 在 Recovery 内制作安装盘并安装

OpenCore 中选择 Recovery。在“磁盘工具”中开启“显示所有设备”，用**容量和名称共同确认**磁盘，把 160GiB 系统盘抹为 GUID / APFS，命名 `macOS`；把专用 32GiB `Installer.raw` 抹为 GUID / Mac OS Extended，命名 `Installer`。不要抹 EFI 或 Delivery 盘。

在 Recovery 终端执行（先上传本仓库脚本到 Delivery，或照脚本手动执行）：

```bash
sh /Volumes/Delivery/build-installer.sh /Volumes/Delivery /Volumes/Installer
```

`build-installer.sh` 对应仓库的 `scripts/macos/build-installer.sh`。它提取 `Payload.cpio` 的安装 app，再把已校验的完整 pkg 用作 app 的 SharedSupport 挂载源，这是该混合容器的特定路径。`createinstallmedia` 会抹掉 Installer 卷。

制作完成后重启，在 OpenCore 选择完整安装盘，安装到 `macOS`。安装会多次重启，中间继续选择 `macOS Installer`，最后选择系统盘；不要每次都选 Recovery。

## 安装后的收尾

创建自己的本地管理员账户，在系统设置开启 SSH 与屏幕共享，先从远端验证均可连接。`sw_vers` 应显示 15.8.1 / 24H32。

正常关机后移除 XML 中的 **Recovery、Installer 和 Delivery** 附加磁盘，仅保留 EFI 与系统盘。否则 OpenCore 可能继续默认进入 Recovery。不要删除唯一 EFI 引导盘。最终 GPU 模板已经移除这些安装介质；驱动切换前仍需创建冷备份。
