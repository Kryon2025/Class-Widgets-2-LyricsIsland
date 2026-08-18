# 歌词岛 (LyricsIsland) — Class Widgets 2 移植版

Class Widgets 2 歌词组件：在本地 `127.0.0.1:50063` 启动 HTTP 服务，接收音乐软件推送的实时歌词，居中显示主歌词与附加歌词（翻译/卡拉OK 副歌词）。

## 📄 许可证与版权声明

本组件是 [LyricsIslandCW](https://github.com/jiangyin14/LyricsIslandCW)（Class Widgets 1 版歌词岛插件）的 Class Widgets 2 移植版，基于 **MIT 许可证** 开源。

**MIT License Copyright (c) 2024 jiangyin14 and 星标**[reference:2]

原插件作者（按贡献先后）：`jiangyin14`、`星标`、`沫烬染`、`Laoshui`、`Xwei1645`[reference:3]

本移植版在保留上述版权声明的前提下，将插件升级适配至 Class Widgets 2。

## 背景

原版 [LyricsIsland](https://github.com/jiangyin14/LyricsIsland) 由 jiangyin14 与 星标 开发，系基于 沫烬染 的“任务栏歌词”插件改造而来[reference:4]。原版在 `127.0.0.1:50063` 监听，向 ClassIsland / ClassWidgets 主界面推送歌词[reference:5]。

本组件**沿用原版的监听端口与数据格式**，因此音乐软件侧无需任何改动即可接入 Class Widgets 2。

## ✨ 特性

- 主歌词 + 附加歌词（翻译）双行显示
- 逐字动画（上浮效果，默认关闭）
- 长歌词自动从右向左滚动（可调速）
- 灵动显示：对比原版，增加了有歌词时显示，无歌词时自动隐藏
- 字号、颜色（白/黑/跟随主题）可配置

## 🔌 接入方式

音乐软件侧通过 POST 推送歌词：

```
POST http://127.0.0.1:50063/component/lyrics/lyrics/
Content-Type: application/json

{"lyric": "当前歌词", "extra": "翻译/附加歌词（可选）"}
```

收到后组件立即显示；未收到歌词时显示等待提示。

### 网易云音乐（推荐）

1. 安装网易云音乐客户端
2. 下载并安装 [BetterNCM](https://github.com/Redns/BetterNCM)
3. 打开 BetterNCM 插件广场，下载并安装 **LyricsIsland** 插件[reference:6]
4. 点击重载，即可将歌词推送到本组件

### 洛雪音乐等其它软件

任意支持向本地 HTTP 接口 POST 歌词的软件，按上述请求格式推送即可。

## 🔌 端口

`50063`（与 Class Widgets 1 版 LyricsIsland 保持一致，音乐软件端无需改动）。请确保本机没有其他程序占用该端口，否则组件无法监听（不影响插件其它功能）。

## 🙏 致谢

- 感谢 [LyricsIsland](https://github.com/jiangyin14/LyricsIsland) 原版作者 **jiangyin14** 与 **星标**
- 感谢 **沫烬染** 的“任务栏歌词”插件为本项目提供参考代码[reference:7]
- 感谢 **Laoshui** 与 **Xwei1645** 对原项目的贡献[reference:8]
- 感谢原版 [LyricsIslandCW](https://github.com/jiangyin14/LyricsIslandCW) 为 Class Widgets 1 提供歌词支持

本移植版基于 MIT 协议发布，完整版权声明见 [LICENSE](./LICENSE) 文件。