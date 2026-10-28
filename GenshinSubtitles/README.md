# 工具入口

完整中文安装和使用说明见仓库根目录 [README.md](../README.md)。

- 首次设置：根目录 `setup.bat`，或 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1`。
- 日常：先正常打开游戏，再运行本目录 `launcher.bat`。
- 环境与回归：`check-environment.ps1 -RunTests`。
- 平台检查：`overlay.ps1 -CheckOnly`；界面检查：`overlay.ps1 -UiCheck`。

仅外部 Windows OCR 和本地官方文本查询。数据、配置、日志、测试截图不进入公开发布包。
