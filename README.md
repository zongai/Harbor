# Harbor（观澜）

**Harbor**（中文名：**观澜**）是原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译、AI 摘要 / 解释 / 对话、Edge TTS 朗读、源分组、评论（Substack / HN / Engadget 等）与离线缓存。

**版本**：Marketing **1.3**；Build 见 `CURRENT_PROJECT_VERSION`。CI 产物展示为 `v1.3-{build}-build{N}`。正式发行以 [Releases](https://github.com/zongai/IosRss/releases) 为准。

> **文档维护**：有意义的功能变更后，构建时默认同步更新 `README.md`（及按约定整理 `CHANGELOG.md`）。CI **不**自动回写文档。

## 功能

### 订阅与分组
- **全库搜索**：300ms 防抖；先标题 / 摘要，再批量补扫已缓存正文；取消上一次任务
- **订阅管理**：添加 RSS / Atom；自动发现常见 feed 路径；源名称可重命名；失败时提示并中止添加
- **源分组**：添加时可指定分组（默认未分组）；移动到分组；分组管理；**分组可折叠**（刷新保留折叠状态）
- **无未读隐藏**：默认只显示有未读的源；设置中开启「显示已读文章」可查看全部
- **源排序**：默认**未读优先自动排序**；可按名称、最近更新或手动拖拽
- **OPML / TXT**：OPML 2.0 导入导出（含分组）；TXT 导出；导出可选保存位置
- **Feed 图标**：RSS/Atom 图 + DuckDuckGo/Google 回退；误标修复后可重试；磁盘缓存与内容缓存隔离
- **源级开关**：全文获取、评论获取、自动翻译、全文 URL 前缀、摘要 Prompt 模板
- **Substack 标识**：识别 Substack 类源并显示徽章；可自动开启评论获取
- **复制源链接**（长按 / 左滑）
- **RSSHub**：Cloudflare 时镜像回退；`rsshub://path` → `https://rsshub.app/path`
- 刷新**线性进度条**（无系统转圈叠层）；失败时标明源名；HTTP 源允许 ATS 并尝试升级 HTTPS

### 阅读
- **全文抓取**：摘要过短时自动或手动抓取；**已有全文可再次点击重新获取**；源可关闭；站点优化含 Foreign Affairs / Foreign Policy / 少数派 / Sixth Tone / SpaceNews / NYT 中文网 / CarNewsChina / **SCMP** 等；遇 **Cloudflare 验证**提示浏览器打开
- **全文 URL 前缀**（设置全局开关 + 前缀，源级启用）：抓取时在文章链接前拼接（如 archive.is / 12ft.io）；缓存仍按原始链接
- **排版**：系统 / 苹方 / 宋体 / 黑体；中西文分排版；首行缩进；清理空段落与广告块；原文压缩留白；链接内图片正确还原（避免 `__IMG_n__` 字面量）
- **工具栏显隐**：向下滑动隐藏顶部导航与底部 Tab；上滑恢复
- **左右滑换篇**：源内或收藏列表内上一篇 / 下一篇
- **TTS**：Edge 在线语音（默认云扬、语速可调）；无需 API Key
- **框选 AI 解释**；**评论**（Substack、Hacker News、Engadget/OpenWeb 等）
- **收藏**（已译显示译文）；**MP3 / 音频卡片**
- **已读**：打开即标已读；文章黑名单（列表显示命中理由）命中自动标已读；清除离线缓存**不**删已读状态
- **相对时间**：30 天内相对时间，超过显示具体年月日
- **阅读进度与高亮**：滚动记录进度；选区可高亮保存

### 翻译与 AI
- **翻译引擎链**：可排序使用列表；限流（429 等）自动切换下一引擎；Google / MyMemory / Lingva / **Yandex** / **Azure·Bing** / Microsoft / DeepL / AI；DeepL·MS 原生批量；结果缓存
- **翻译目标语言**与 **AI 输出语言**可分别配置
- 列表 / 阅读页自动翻译（按源开关）；**全文抓取完成前不自动翻译正文**；阅读页重新翻译**可选引擎**
- 并发可调；多 Key 轮询；设置内连通性测试
- **AI Provider 多模型**：每 Provider 可配置模型列表与默认模型；可选**经济模型**做费用路由
- **模型费用路由**：短文本用经济模型，长文摘要与解释用强模型
- **Prompt 预设**：内置标准/科技/学术/投资/新闻/评测等，可**添加自定义类型**并编辑模板；全局 + **按源**覆盖
- **AI 摘要**：按 Prompt 预设生成；失败自动切换 Provider
- **兴趣过滤**：收藏 / 「不感兴趣」学习词权重；文章打分；低分可沉底或自动已读；列表可按兴趣排序
- AI 摘要 / 解释 / **独立对话页**（历史管理）；失败自动切换 Provider；每 Provider 多 Key
- AI 黑名单；文章黑名单；Key 存钥匙串

### 外观与字体
- **外观**：跟随系统（默认）/ 浅色 / 深色
- **阅读主题（6 套）**：Classic Light / Sepia Paper / Night Dark / Midnight Blue / Forest Sage / High Contrast
- **字体**：系统默认、苹方、宋体、黑体；分区字号可调；**Dynamic Type** 跟随系统更大字体
- **Editorial UI**：Design Tokens（间距 / 圆角 / 阅读列宽 / 动效）；文章列表 Featured 首条 + 标题→摘要→元数据；阅读页杂志层级（源名→标题→元信息→正文）；正文 h1–h3 / 引用块独立样式；订阅列表 plain 扁平；工具栏主操作 + ⋯ 溢出；阅读进度细条；减弱动态效果兼容
- SwiftUI Pro 无障碍：合并 VoiceOver 标签、约 44pt 点击区、带标签的 Button/Menu

### 其它
- 离线缓存（全文 / Feed 快照 / 图片）；清除缓存保留订阅与已读
- 设置备份导入 / 导出
- CI：打 `v*` 标签产出 unsigned IPA 与 Release 说明（不回写文档）

## 结构

```
Harbor/
├── App.swift / ContentView.swift / Info.plist
├── Theme/          # 设计 tokens、阅读主题、字体
├── Models/
│   ├── AppStore.swift           # 订阅数据与协调入口
│   ├── FeedModels.swift         # Feed / Article 等模型
│   ├── SessionChromeState.swift # 刷新/列表翻译进度（独立观察）
│   └── SettingsStore.swift      # 用户偏好与引擎配置（独立观察）
├── Services/
│   ├── FeedRepository / SettingsRepository / OfflineCache
│   ├── FeedRefreshService / FeedParser / NetworkURLPolicy
│   ├── ArticleContentFetcher / RequestDeduper / ImageDownsampling
│   ├── ArticleSearchService / CommentFetcher
│   ├── TranslationCoordinator / TranslationServices
│   ├── AIService / EdgeTTS / ICloudSyncService
└── Views/          # SwiftUI：订阅、列表、阅读、搜索、收藏、对话、设置
```

状态大致分为：订阅数据（`feeds`）· 会话进度（`chrome`）· 偏好（`settings`）。

## 要求

- Xcode 16+ / iOS 18.0+
- Swift 5

打开 `Harbor.xcodeproj` 即可编译运行。

## 设置说明

设置页分区（与代码一致）：

| 分区 | 内容 |
|------|------|
| 账号 | iCloud 云同步与状态 |
| 阅读 | 标题模式、字号分区、外观与阅读主题、字体、朗读（Edge TTS） |
| 订阅 | 显示已读、源排序等 |
| AI | Provider、经济模型、Prompt 预设、兴趣过滤、黑名单；翻译引擎链与目标语言在子页 |
| 数据 | 已读保留天数、全文缓存、全文 URL 前缀、清除离线缓存、OPML 导入/导出、设置备份 |
| 关于 | 版本与相关说明 |

部分翻译 Key、AI Key 存于 **Keychain**（第三方服务，需自备 Key 的引擎除外）。

## 版本号

| 字段 | 来源 |
|------|------|
| Marketing（`CFBundleShortVersionString`） | `MARKETING_VERSION`，当前 **1.3** |
| Build（`CFBundleVersion`） | `CURRENT_PROJECT_VERSION`（随发布构建递增） |
| CI 展示 | `v1.3-{build}-build{run_number}`（见设置页 / AppVersion） |

正式功能以 **main** 与 GitHub Releases 为准。开发分支（如 `ui-redesign-experiment`）上的 UI/性能改动可能尚未并入正式 Release。

最新构建见 [GitHub Releases](https://github.com/zongai/IosRss/releases) 与 [Actions](https://github.com/zongai/IosRss/actions)。

## 已知限制

- 全文抓取依赖站点 HTML 结构；遇 Cloudflare 等人机验证时需在浏览器打开。
- 搜索先匹配标题与摘要；有磁盘正文时再异步批量补全命中。Feed 支持条件请求（304）；离开订阅列表会取消进行中的全量刷新。
- 翻译 / AI 依赖第三方 API；限流、可用性与费用由各服务方决定。
- Edge TTS 为在线服务，需网络。
- Bundle ID 仍为示例 `com.example.Harbor`，上架前需自行更换。

## Changelog

见 [`CHANGELOG.md`](./CHANGELOG.md)。

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

Copyright (c) 2026 zongai
