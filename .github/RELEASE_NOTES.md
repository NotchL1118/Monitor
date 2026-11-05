下载与你的 Mac 芯片匹配的 ZIP，解压后将 `Monitor.app` 移到「应用程序」文件夹：

- **Apple Silicon（M 系列）**：`Monitor-<版本>-macos-arm64.zip`
- **Intel**：`Monitor-<版本>-macos-x86_64.zip`
- **SHA256SUMS.txt**：下载文件的 SHA-256 校验值。

要求 macOS 14 或更新版本。Chrome 扩展已包含在应用中，可通过「连接与设置」打开扩展所在目录，再在 Chrome 中「加载已解压的扩展程序」。

当前构建使用 ad-hoc 签名，尚未进行 Apple Developer ID 签名和公证。首次打开可能被 macOS 拦截；确认下载来源后，可在「系统设置 → 隐私与安全性」中允许打开。
