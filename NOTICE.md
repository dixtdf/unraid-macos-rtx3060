# 来源与许可证

本仓库原创教程、辅助脚本和原生验收源码使用根目录 MIT License。

`templates/opencore-1.0.5.plist` 基于 LongQT OpenCore ISO v0.7 的配置，包含本次实际安装的调整与脱敏。来源：[LongQT-sea/OpenCore-ISO](https://github.com/LongQT-sea/OpenCore-ISO)。根据其 MIT 许可证保留完整声明：

```text
MIT License

Copyright (c) 2024-2025, LongQT-sea

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

文档引用但不随仓库分发的项目保留各自许可证：

| 项目 | 用途 / 固定版本 | 官方来源 |
| --- | --- | --- |
| NullMoth NVIDIA Driver | 1.1.0 驱动及配套固件 | [v1.1.0](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v1.1.0) |
| OpenCorePkg | 1.0.5、ocvalidate、macserial、macrecovery | [1.0.5](https://github.com/acidanthera/OpenCorePkg/tree/1.0.5) |
| VirtualSMC | 1.3.7，`-vsmccomp` 行为说明 | [源码](https://github.com/acidanthera/VirtualSMC/blob/1.3.7/VirtualSMC/kern_vsmc.cpp) |
| Lilu / WhateverGreen | EFI 基础中使用的插件 | [Lilu](https://github.com/acidanthera/Lilu)、[WhateverGreen](https://github.com/acidanthera/WhateverGreen) |
| QEMU / libvirt | 虚拟机运行与管理 | [QEMU](https://www.qemu.org/)、[libvirt](https://libvirt.org/) |
| Apple macOS / 安装包 / SMC OSK | 使用者自行取得 | [Apple 安装器说明](https://support.apple.com/102662) |

这里的 MIT 许可不覆盖 Apple 软件、NVIDIA 固件、第三方 EFI / kext 或上游驱动二进制。不要把这些下载文件、自己的完整 EFI 镜像或已填身份的配置直接加入公开仓库。
