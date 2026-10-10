# 7. 冷备份、恢复与 GitHub 发布

## 建立完整恢复点

每个关键阶段完成后，正常关机并确认 `virsh domstate` 为 `shut off`，再备份 **系统 qcow2、可写 EFI raw、OVMF NVRAM、libvirt XML**。仅保存 config.plist 无法恢复驱动写入的辅助内核集合或系统文件。

使用本仓库路径布局时：

```bash
bash scripts/unraid/checkpoint.sh macos15 /mnt/user/domains/macos15
```

脚本拒绝运行中的 VM，检查磁盘路径不逃出 VM 目录、当前 XML 引用预期文件、qcow2 检查通过，复制到唯一新目录并生成 SHA256SUMS。reflink 支持时减少复制成本，始终保留独立文件，不能把可写引导盘与备份做硬链接。备份过程中禁止其他管理者、自动任务或 UI 启动 VM；脚本末尾的状态检查不能替代这个约束。

现有 VM 若使用不同文件名或把 NVRAM 放在 libvirt 默认目录，先按实际 XML 调整备份文件清单；脚本会拒绝模板以外的路径，不能当成自动发现所有磁盘的通用工具。附加业务磁盘也要纳入自己的备份方案。

建议保存：纯安装完成、GPU 直通前、驱动通过验收后、电源修复后四个恢复点。本次最后完整冷备份的 `qemu-img check` 无错误。

## 恢复

1. 正常停止 VM 并确认 QEMU 不再使用磁盘；当前不能启动的 VM 也检查宿主机进程 / VFIO 占用。
2. 在备份目录执行 `sha256sum -c SHA256SUMS`，再 `qemu-img check -f qcow2 vdisk1.qcow2`。
3. 把当前 EFI、系统盘、NVRAM、XML另存到一个新目录，保留故障证据。用备份替换对应文件，所有目标必须是已核实的 VM 专用绝对路径。
4. 从备份 XML 恢复定义，再检查 UUID / MAC、PCI BDF、OVMF 路径、BAR 启动钩子与磁盘路径。恢复后先手动启动验证。

恢复“GPU 前”的检查点时，也恢复其虚拟显示器和对应 EFI 配置；恢复“GPU 后”的检查点时仍需要 BAR1 8GiB。不要把不同时间点的系统盘、EFI、NVRAM随意混用。

如果 macOS 仍能进入系统，驱动包提供 `uninstall.sh` 及安装器打印的 backup 路径。核实其对应本次安装后按上游说明卸载；若系统不能启动，优先完整冷备份回滚。不要在原系统盘上反复试验未知的 KC 重建命令。

## 本地仓库检查

本仓库没有上传 Apple 安装介质、驱动二进制、EFI 镜像、真实身份或密码。`local/`、`media/`、`vendor/`、`backups/` 等已忽略；**忽略规则不保护以前已提交的文件**。

在仓库目录运行：

```powershell
py -3 -m unittest discover -s tests -v
py -3 tools/check_publication.py
git status --short
git ls-files
```

检查器会检查工作区与暂存区，也包含已被跟踪但后来忽略的文件，报告命中的文件名和规则，不打印秘密本身。它不扫描 Git 历史，不保证发现每一种凭据、公网私人域名、截图或外部日志。自己再核对这些内容，尤其是完整 XML 中的 OSK 和 plist 中的身份。

若秘密已提交：先撤回暂存或移除跟踪，再按情况处理历史与已经泄露的凭据；只增加 `.gitignore` 不够。不要把私有文件换个目录后加入 Git。

## 首次发布到自己的 GitHub

项目仓库为 [dixtdf/unraid-macos-rtx3060](https://github.com/dixtdf/unraid-macos-rtx3060)。如果将这套资料发布到自己的新仓库，先在 GitHub 建立空仓库，再从目标目录执行以下示例；如果目录已初始化 Git，省略 `git init`，并把远端地址换成自己的仓库：

```powershell
git init -b main
py -3 tools/check_publication.py
git add .
py -3 tools/check_publication.py
git diff --cached --stat
git commit -m "Document Unraid macOS 15.8.1 RTX 3060 installation"
git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

确认 `git remote -v` 指向自己的仓库后再 push。CI 会执行离线模板测试、隐私规则检查和 shell 语法检查，不会运行虚拟机或宣称硬件验收通过。

对外介绍建议使用准确范围：“RTX 3060 12GB 在 Unraid 上运行 macOS 15.8.1，Metal 小规模验收及 H.264 编解码通过，HEVC 硬件编码仍有画面错误。”不要写成“全部 RTX 全功能支持”或“HEVC 编码已解决”。
