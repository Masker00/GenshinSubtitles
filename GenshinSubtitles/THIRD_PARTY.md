# 第三方来源与权属

- Windows OCR、WinForms 和 .NET Framework 是 Windows 平台组件；本仓库仅调用其 API，不分发这些系统组件。
- Python 解释器由用户安装；查询/建库工具仅用 Python 标准库，不附带解释器或第三方 Python 包。
- TextMap 来自社区提取仓库 `DimbreathBot/AnimeGameData`，固定提交、版本标记和四文件 Git blob 校验见 `data/sources.json`。感谢 Dimbreath 的提取与维护。下载器仅使用固定原始文件及同一 Git blob API。
- 游戏文本及游戏相关名称归原权利人所有。社区提取不改变其权属，工具代码的 MIT 许可不会给游戏文本附加许可。公开包不包含 TextMap 或 SQLite。
- 查询回归与 OCR 合成图测试包含少量用于验证的官方台词，不应描述为原创台词；文档设置截图由本项目 UI 自检生成，不含玩家信息。
- 本项目是非官方工具，与米哈游/HoYoverse 无关联，不保证与所有游戏版本或窗口模式兼容。

工具代码采用 MIT 许可证，见根目录 LICENSE；游戏文本不纳入该许可。未引入其他启动器、注入器或历史研究源码。
