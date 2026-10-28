# 开发与维护

这是一个 Windows PowerShell 5.1 / WinForms 小工具，不建立完整 .NET 多项目工程。新增 ps1 优先 ASCII；含中文的脚本保存为 UTF-8 BOM，以兼容 5.1。

## 代码地图

| 文件 | 责任 |
|---|---|
| `GenshinSubtitles/overlay.ps1` | 检查前置条件、组装模块、选择运行/自检、最终释放窗口 |
| `setup.bat`、`setup.ps1`、`launcher.bat` | 首次设置与日常启动，保留可读失败提示 |
| `resolve-python.ps1`、`check-environment.ps1` | Python 选择与环境/回归检查，无开发者路径 |
| `modules/platform.ps1`、`native/Dpi.cs` | 系统/DPI 初始化、有效游戏窗口边界 |
| `modules/ui.ps1`、`native/OverlayWindows.cs` | 设置、工具栏、选区、透明字幕、原有字号和交互 |
| `modules/config.ps1` | 默认值、旧配置迁移、验证、统一更新与原子保存 |
| `modules/runtime.ps1` | 单任务调度、世代/上下文检查、UI 线程取回结果、短暂缓存、快捷键 |
| `scan-worker.ps1`、`native/ScanJob.cs` | 后台扫描，Windows Job Object 包含进程及 Python 后代、超时/退出回收 |
| `modules/capture.ps1`、`modules/query.ps1` | 截图/WinRT OCR 及受限时的 Python 调用 |
| `tools/lookup_ocr_text.py` | 可导入查询函数 + CLI；原始中英文本、ID、匹配方式/相似度 |
| `tools/build_ocr_index.py`、`tools/index_schema.py` | v2 索引、原文与检索键分离、源内容指纹/结构校验 |
| `fetch-data.ps1`、`prepare-ocr-index.ps1` | 固定四文件校验与按需建库 |
| `tests/` | 查询、配置、工作进程及既有 UI 回归 |
| `tools/package_public.py`、`release-files.txt` | 独立公开打包允许清单、校验和审计 |

## 运行规则

只有主线程接触 UI 和 config。每次扫描交给一个独立 PowerShell 进程；进程入 Job Object 前以 stdin 阻塞启动，退出/超时关闭 job 时会结束 Python 后代。没有任务队列：忙时跳过，完成后重新取当前画面；自动任务总超时 15 秒，单次查询 10 秒，异常后 2 秒再试。

识别语言、OCR 区域、窗口身份/边界、索引文件长度/修改时间组成上下文，另有单调递增任务世代。UI 先校验当前窗口/数据/设置，再接收结果；SET、停用、选区/识别语言变化会取消旧任务。查库成功的相同 OCR 文本可缓存最多 30 秒；未匹配每次有效扫描重试。源内容更新后必须重建索引，其指纹在准备流程校验。

连续空/短输入会清空字幕；无新有效文本最多保留 6 秒，异常、游戏失效和停用立即清空。显示语言切换使用当前同一条记录，不能恢复已经清除的旧字幕。

`Update-OverlayConfig` 为设置页/工具栏更新入口；选区拖动按既有坐标规则更新临时位置并在松手时经过统一校验/保存。运行状态从不写入配置。损坏 JSON 保留原文件并禁用保存；正常写入同目录临时文件后 File.Replace，保存一份 `.bak`。UI 测试每次从独立随机配置目录开始。

## 测试命令（仓库根目录）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GenshinSubtitles\check-environment.ps1 -RunTests
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GenshinSubtitles\overlay.ps1 -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GenshinSubtitles\overlay.ps1 -UiCheck
```

纯 Python 回归可在没有数据时生成临时微型数据库；存在真实索引时追加 Medium/真实 OCR 查询。配置测试不需要桌面；worker/UI 测试需要已安装 Windows OCR 和交互桌面。UI 检查使用程序化窗口消息，不能替代游戏内手动验收。不因没有游戏而把游戏验收写成通过。

## 本地文件

- `GenshinSubtitles/data/`：四份 TextMap、索引、个人配置及 `.bak`；只允许清单 `sources.json` 进入 Git。
- `overlay.ps1 -ConfigDirectory <目录>` 可供隔离调试使用；UiCheck 始终使用其独立随机目录。
- `GenshinSubtitles/test-results/`：自检图片与随机隔离配置，全部忽略。
- `GenshinSubtitles/overlay-errors.log`、系统临时目录启动日志：排错信息，可能含实际路径，不公开。
- `.local/`：本地验证证据和临时干净目录，不公开。
- `%TEMP%/genshin-scan-*`：单次任务请求与图片，正常退出/取消时清理。
- `dist/`：候选 ZIP 与 SHA-256，非源码提交项。

## 公开打包

```powershell
. .\GenshinSubtitles\resolve-python.ps1
$subtitlePython = Resolve-SubtitlePython
& $subtitlePython .\tools\package_public.py --output .\dist\GenshinSubtitles-v0.1.0-beta.1-candidate.zip
& $subtitlePython .\tools\package_public.py --verify .\dist\GenshinSubtitles-v0.1.0-beta.1-candidate.zip
```

仅打包 `release-files.txt` 明确列出的文件，路径不得越界或为链接；包内生成文件哈希清单和打包状态，旁边生成 ZIP SHA-256。`--require-final-license` 在许可证仍待确认时拒绝生成可公开发布包。源码/候选 ZIP 都不含数据、配置、游戏路径、历史研究、日志或用户信息。

发布前：确认账号/组织、仓库名、最终许可与版权署名、现在公开的授权；替换 LICENSE、更新候选说明后重新测试与打包。再创建公开仓库、添加 remote、推送 main、创建版本 tag/Release、上传 ZIP/校验文件。未获得上述授权时只交付本地可审查候选。
