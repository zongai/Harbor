# Changelog

本文件由**维护者手动更新**，GitHub Actions **不会**自动改写。

**约定：每个正式条目对应一次成功构建**（上一成功构建标签 → 本成功构建标签之间的全部变更），不按中间未构建版本号逐条拆分。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [1.3-76] — 构建成功 (build158 / Actions 35446479020)

### 翻译
- 新增 **Yandex（免 Key）**、**Azure/Bing（免 Key）** 引擎（参考 Readest 网页 API）
- DeepL / Microsoft 列表翻译走原生多句批量；缺口单条补齐
- 翻译结果缓存 + 译文润色（中/日等标点）
- DeepL 简繁码改为 `ZH-Hans` / `ZH-Hant`（避免全大写失败）
- Google 全局并发闸（最多 4 路），降低 429

### 全文 / 阅读
- **SCMP** 全文：从 `__NEXT_DATA__` 提取正文与封面，自动抓取可用
- 全文请求忽略本地空壳缓存；有正文时减少 CF 误判

### 体验
- AI 对话页滑动消息列表收起键盘
- 列表/阅读滚动与换篇相关优化延续

## [1.3-77] — 构建成功 (build159 / Actions 35455863195) · 分支 ui-redesign-experiment

相对：`v1.3-76` / 1.3-76 成功构建

### 品牌
- 项目更名为 **Harbor**（中文 **观澜**）
- 主屏显示名：中文系统 **观澜**，英文系统 **Harbor**
- Bundle ID `com.example.Harbor`；钥匙串 / 离线缓存 / iCloud 键 / 工程目录与 Target 均改为 Harbor
- 导出文件名、CI IPA / Release 标题：Harbor-*

### UI / 体验（Editorial 重设计实验）
- **Design Tokens**：`AppSpacing` / `AppRadius` / `AppLayout` / `AppMotion`；`readingColumn()` 大屏居中阅读列
- **阅读页**：源名→大标题→元信息层级；正文行距/段距；h1–h3 与 blockquote 独立样式；图片 continuous 圆角；工具栏主操作（收藏/翻译）+ ⋯ 溢出（全文/摘要/朗读/评论/浏览器/分享）；细阅读进度条
- **列表**：首条 Featured 行；标题→摘要→元数据；订阅页 plain 扁平 + 安静空/加载态
- **搜索 / 评论 / 对话 / 添加订阅 / 设置**：对齐 tokens 与主题背景（`appFormChrome`）
- **无障碍**：Dynamic Type（UIFontMetrics）；Reduce Motion；列表合并 VoiceOver 标签；约 44pt 点击区

## [1.3-78] — 构建成功 (build160 / Actions 35483862757) · 分支 ui-redesign-experiment

相对：`v1.3-77` / build159

### 品牌（完整重命名）
- 工程 / Target / 源码目录：`Harbor`
- Bundle ID `com.example.Harbor`；钥匙串、离线缓存、URLCache、iCloud 键全部改为 Harbor
- 主屏显示名：中文 **观澜**，英文 **Harbor**
- CI scheme 与路径同步更新

## [1.3-79] — 构建成功 (build162 / Actions 35486533768) · 分支 ui-redesign-experiment

相对：`v1.3-78` / build160

### 设置
- 分区重组：账号 → 阅读 → 订阅 → AI → 数据 → 关于（对齐产品信息架构）
- 设置内支持 OPML 导入/导出

### 阅读
- 去掉正文与页头重复的标题；表格不再双表头
- 滚动叠字：正文改 VStack、关闭 UITextView 非连续布局、chrome 动画与滚动内容隔离

### 全文抓取
- Visual Capitalist：模糊占位/同图去重，避免清晰+模糊双图
- Phys.org：article-main 正文提取，去掉相关推荐与 Explore further 等噪音

### 评论
- Editorial 层级、主题背景、楼中楼竖线、空/错状态精修

## [1.3-80] — 构建成功 (build163 / Actions 35487359347) · 分支 ui-redesign-experiment

相对：`v1.3-79` / build162

### 性能
- 已读/收藏：feeds 全量落盘 1.2s 防抖；read links 仍即时写入
- 刷新：Fetch + XML 解析在 Task.detached，主线程只合并状态
- 搜索：320ms 防抖、取消上一次任务、默认不扫正文 HTML

## [1.3-81] — 构建成功 (build164 / Actions 35493004976) · 分支 ui-redesign-experiment

相对：`v1.3-80` / build163

### 性能
- 元数据与正文分离：大正文/译文落 OfflineCache，内存按需水合
- 图片 ImageIO 降采样（Feed 图标 + 阅读页配图）
- 全文抓取 RequestDeduper 去重
- 观察面：已读/收藏不再整源替换（articleFlagsEpoch）

## [1.3-82] — 构建成功 (build167 / Actions 35493905811) · 分支 ui-redesign-experiment

相对：`v1.3-81` / build164

### Changed
- **SettingsStore**：字体 / 主题 / 翻译与 AI 等偏好独立 `@Observable`；AppStore 以计算属性桥接访问
- **SessionChromeState**（既有）：刷新与列表翻译进度与订阅数据分域观察
- 设置页使用 `Bindable(settings)` 绑定偏好字段
- 列表翻译工具栏进度 `ListTranslationChromeProgress` 仅观察 `chrome`
- 阅读页翻译 / 摘要继续使用本地 `@State`，不写入 AppStore

### Fixed
- 设置子视图误注入 `store` 绑定导致编译失败（ProviderTag 等）

## [1.3-88] — 构建成功 (build173 / Actions 35524322354) · 分支 ui-redesign-experiment

相对：`v1.3-87` / build172

### 阅读
- 表格可视性精修：表头分隔、斑马纹、列宽估算、网格线与外边框
- 点击配图全屏查看：双指缩放、拖动、双击放大/复位；尝试更高清解码

## [1.3-87] — 构建成功 (build172 / Actions 35523135145) · 分支 ui-redesign-experiment

相对：`v1.3-86` / build171

### 图片 / Visual Capitalist
- 整页收集 og:image、uploads、锚点大图并插入文首（解决正文有字无图）
- Photon 与源站 URL 互备重试；加载中/失败占位可点重试
- 阅读解析优先大图 srcset；图片文件链接按配图显示

## [1.3-86] — 构建成功 (build171 / Actions 35519184531) · 分支 ui-redesign-experiment

相对：`v1.3-85` / build170

### 图片 / Visual Capitalist
- 提升 `srcset`、锚点大图、`<picture><source>` 为可用 `src`
- 清洗不再因裸 `subscribe` 误删含图正文
- 去重至少保留一张图；缺图时用 `og:image` / 页内 uploads 兜底
- Jetpack Photon（`*.wp.com`）加载使用 visualcapitalist.com Referer

## [1.3-85] — 构建成功 (build170 / Actions 35518273081) · 分支 ui-redesign-experiment

相对：`v1.3-84` / build169

### 全文抓取
- 修复自动获取被跳过：水合 RSS 摘要缓存时不再误标 `hasFullContent`
- 未真正抓成功过全文时始终自动尝试（长摘要不再冒充全文）
- 静默自动抓取在未确认全文时强制走网络
- hartpunkt.de 不再优先 WP REST（401），直接 HTML 提取

## [1.3-84] — 构建成功 (build169 / Actions 35517021723) · 分支 ui-redesign-experiment

相对：`v1.3-83` / build168

### 设置 / 备份
- 去掉「高级 / 精简」开关，设置项始终全部可见
- 设置导出 **v4**：全文 URL 前缀、源级开关与分组、翻译链、字体/语言、兴趣过滤与模型路由等完整偏好
- 主题配色精修（Forest / Sepia 深色下保持色相）

### 列表
- 取消首条 Featured 突出样式，统一 `ArticleRow`

### 全文抓取
- 误标 `hasFullContent` 阻断正文：恢复与重抓逻辑
- **hartpunkt.de** / **SpaceNews** / **NYT 中文网** 正文提取与清洗
- SpaceNews 优先 WordPress REST；段落级拼装
- 再次点击「获取全文」可 **强制重新抓取**（跳过本地缓存）

### 图片
- **Sixth Tone**：`illustrationWrap` 按 `data-index` 插入 `textImageList` 配图
- 配图请求带站点 Referer；扩展懒加载字段；expreview 容器选择器

## [1.3-83] — 构建成功 (build168 / Actions 35495833175) · 分支 ui-redesign-experiment

相对：`v1.3-82` / build167

### Added
- **MIT License**（Copyright (c) 2026 zongai）。见 [LICENSE](LICENSE)

### Performance / Architecture
- **正文按 link 统一读写**：列表只持元数据；`OfflineCache.persistArticleBody` / `loadArticleBody`；阈值约 400 字即落盘
- **feeds.json 元数据快照**：编码前剥离大正文；已读/收藏链接集即时落盘；进后台 `flushPendingFeedsPersist`
- **文章级标志索引**：`ArticleFlagsIndex` + 按源 `articleSnapshot`；未读增量维护；`articleID → feedID` 辅助索引
- **订阅分组 section 快照**：仅 feeds/排序/折叠相关字段变化时重建
- **搜索**：300ms 防抖、取消上一次；先标题/摘要，再 batch 补全文命中
- **Feed 条件请求**：ETag / Last-Modified / 304；`FeedRequestGate` 全局限流；离开订阅列表取消全量刷新
- **全文 in-flight**：同 canonical link 共享 Task；下层 RequestDeduper
- **刷新**：`nonisolated` Fetch/Parse，`Article: Sendable`，主线程只 merge
- **图片**：ImageIO thumbnail 略提清晰度（scale×1.15）
- **iCloud**：settings / catalog / readState 分档防抖推送
- **相对时间**：按分钟桶缓存格式化字符串
- **TranslationCoordinator**：引擎可用性与 failover 查询下沉（执行仍在 AppStore）

---



## [v1.3-75] — 2026-09-18

成功构建：`v1.3-75-build157`  
相对：`v1.3-74-build-20260913110855`

### Added
- 全文抓取识别 Cloudflare 人机验证，提示并用浏览器打开
- 阅读页重新翻译可选具体翻译引擎
- 阅读页状态栏/导航栏配色跟随阅读主题，提高时间与信号栏对比度

### Fixed
- 订阅列表刷新：结束系统下拉转圈，仅保留线性进度条
- 原文排版：`<a>` 包裹图片不再显示 `__IMG_0__` 字面量；折叠空行与空 figure/svg
- 长文阅读滚动卡顿：LazyVStack、解析缓存、UITextView 内容未变跳过重建

### Changed
- 列表性能：避免全库 flatMap 查文章；行 id 精简；翻译批次统一落盘；语言判定抽样
- HTML 解析正则静态缓存；长文后台解析；全量刷新进度更新去掉逐步动画

---

## [v1.3-74] — 2026-09-13

成功构建：`v1.3-74-build-20260913110855`  
相对：`v1.3-73-build-20260913074815`

### Removed
- 系统翻译（Apple Translation）整条链路与设置项；默认引擎改回 Google

### Changed
- RSSHub 请求使用 Folo Mobile UA 与 X-App-Name / X-App-Platform 头

---
## [v1.3-73] — 2026-09-13

成功构建：`v1.3-73-build-20260913074815`  
相对：`v1.3-72-build-20260913073215`

### Fixed
- 系统翻译按官方 Configuration + translationTask 重写；明确源语言；超时回退；iOS 26 直接 Session

---

## [v1.3-72] — 2026-09-13

成功构建：`v1.3-72-build-20260913073215`  
相对：`v1.3-71-build-20260913072048`

### Added
- 阅读页显示译文实际使用的翻译引擎

### Fixed
- 系统翻译卡住：translationTask 宿主、超时与失败回退

---

## [v1.3-71] — 2026-09-13

成功构建：`v1.3-71-build-20260913072048`  
相对：`v1.3-66-build-20260913053406`

### Added
- 系统翻译（Apple Translation）：默认优先本地；支持重新翻译 / 更高质量重译（跳过系统引擎）

### Fixed
- 系统翻译编译与 Menu primaryAction 参数顺序等问题

### Removed
- 背景补全：阅读页展示、摘要后自动生成、摘要嵌入与相关 AIService/AppStore API

---

## [v1.3-66] — 2026-09-13

成功构建：`v1.3-66-build-20260913053406`  
相对：`v1.3-65-build-20260913052214`

### Removed
- 背景补全：阅读页展示、摘要后自动生成、摘要嵌入与相关 AIService/AppStore API

---

## [v1.3-65] — 2026-09-13

成功构建：`v1.3-65-build-20260913052214`  
相对：`v1.3-64-build-20260913051257`

### Fixed
- 阅读页翻译按钮：译完后可在「原文 / 译文」间切换，按钮不再消失

---

## [v1.3-64] — 2026-09-13

成功构建：`v1.3-64-build-20260913051257`  
相对：`v1.3-63-build-20260913045926`

### Fixed
- 横向滑表格时不误触发换篇
- 表格内 `_IMG_O_ Israel` 等占位映射为国旗 emoji

---

## [v1.3-63] — 2026-09-13

成功构建：`v1.3-63-build-20260913045926`  
相对：`v1.3-62-build-20260913044842`

### Fixed
- 翻译时整表占位跳过，保留表格样式；增强懒加载/srcset 图片解析与 VC 特色图

---

## [v1.3-62] — 2026-09-13

成功构建：`v1.3-62-build-20260913044842`  
相对：`v1.3-61-build-20260913042456`

### Added
- 阅读页 HTML 表格渲染（`ContentBlock.table` + `ArticleTableView`）
- Visual Capitalist 等图表站：WordPress REST 按 slug 取全文；增强图/表抽取

---

## [v1.3-61] — 2026-09-13

成功构建：`v1.3-61-build-20260913042456`  
相对：`v1.3-60-build-20260913040559`

### Fixed
- 设置高级选项开关、阅读页崩溃、列表卡顿、缓存界面相关修复

---

## [v1.3-51] — 2026-09-12

成功构建：`v1.3-51-build-20260912055613`  
相对：`v1.3-50-build-20260912020652`

### Fixed
- 源图标：不再在仅解析 URL 时标记 fetchDone；优先 PNG 候选；旧失败缓存本会话可重试

### Added
- 订阅源可复制链接（长按 / 左滑）
- Substack 类源列表显示橙色标识
- 添加源失败时提示并中止（无效 HTTP、无法解析、无标题且无文章、重复源）

---

## [v1.3-50] — 2026-09-12

成功构建：`v1.3-50-build-20260912020652`  
相对：`v1.3-49-build-20260912014132`

### Added
- AI Provider 支持多模型：可配置模型列表与默认模型；对话页可按模型切换

---

## [v1.3-49] — 2026-09-12

成功构建：`v1.3-49-build-20260912014132`  
相对：`v1.3-48-build-20260911133046`

### Fixed
- 刷新时保留分组折叠/展开状态（稳定 section id，禁用刷新写入动画）
- 添加订阅未选择分组时不再误入分组（Picker 默认「未分组」）

### Changed
- 保留刷新进度条；列表结构更新不再带动折叠动画

---

## [v1.3-48] — 2026-09-11

成功构建：`v1.3-48-build-20260911133046`  
相对：`v1.3-47-build-20260910203058`

### Added
- AI 对话页（Tab）：仅限已配置 API Key 的 Provider；多轮上下文；本地历史与重命名/删除/清空
- Sixth Tone 全文：从 `__NEXT_DATA__` 提取正文与 `textImageList` 配图

### Fixed
- 源开启自动翻译时：打开文章即使标题已译，正文非目标语言仍自动翻译
- 超过 30 天的文章时间显示为具体年月日

---

## [v1.3-47] — 2026-09-10

成功构建：`v1.3-47-build-20260910203058`  
相对：`v1.3-43-build-20260910111644`

### Added
- 多 Key 自动轮询与冷却：无效 Key（约 1 小时）、限流 Key（约 5 分钟）自动跳过（AI / DeepL / Microsoft）
- 兼容 AI 思考模型：忽略 `reasoning` / Gemini `thought` parts；剥离 `<think>` 等标签，界面不展示思考过程

### Changed
- Google 翻译改回纯免 Key（`client=gtx` GET/POST），移除多 Key / 官方 API；默认串行以降低限流
- 刷新加速：最多 8 源并行；专用 Session；超时缩短；批量落盘

---

## [v1.3-43] — 2026-09-10

成功构建：`v1.3-43-build-20260910111644`  
相对：`v1.3-41-build-20260910105022`

### Changed
- Google 无 Key：优先 GET `translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=…&dt=t&q=…`（长文本回退 POST）

### Improved
- 测试 Key 时在每个 Key 行旁直接显示「可用 / 不可用」

---

## [v1.3-41] — 2026-09-10

成功构建：`v1.3-41-build-20260910105022`  
相对：`v1.3-38-build-20260910103959`

### Fixed
- 左右滑换篇后滚动回到文章开头

### Improved
- DeepL / Google / Microsoft：多 Key 失败时自动切换；Google 全失败可回退免 Key
- Lingva 公共实例更新（含 `lingva.ml`、plausibility、lunar.icu、projectsegfau、garudalinux）

---

## [v1.3-38] — 2026-09-10

成功构建：`v1.3-38-build-20260910103959`  
相对：`v1.3-35-build-20260910101755`

### Added
- 恢复 Lingva：REST v1 GET/POST，公共实例轮询 + 可选自定义实例

### Fixed
- Google 429：退避重试、降低默认并发、错误不再刷 HTML
- 翻译 / AI 测试标明每个 Key 是否可用（掩码）

---

## [v1.3-35] — 2026-09-10

成功构建：`v1.3-35-build-20260910101755`  
相对：`v1.3-32-build-20260910093639`

### Removed
- 移除当时不可用的 Lingva、LibreTranslate（原选择回退 Google）

### Fixed
- Microsoft 翻译 401：增加 `Ocp-Apim-Subscription-Region`，设置可填 Azure 区域

### Added
- 各翻译引擎「测试此引擎」连通性 / Key 检测

---

## [v1.3-32] — 2026-09-10

成功构建：`v1.3-32-build-20260910093639`  
相对：`v1.3-31-build-20260909140457`

### Added
- DeepL 多 Key + 配额耗尽切换 / 回退 Google

### Improved
- Google POST + 高连接数 Session；Microsoft 批量并行

---

## [v1.3-31] — 2026-09-09

成功构建：`v1.3-31-build-20260909140457`  
相对：`v1.3-28-build-20260909132331`

### Fixed
- 并发翻译：取消 AI 跨 Provider 分片，恢复单链路 failover
- 提高默认并发与列表批次，避免小批串行拖慢速度

### Changed
- 文章是否已翻译 / 是否需翻译以**正文**为准

---

## [v1.3-28] — 2026-09-09

成功构建：`v1.3-28-build-20260909132331`  
相对：`v1.3-21-build-20260909121250`

### Added
- AI Provider 多 API Key（轮询 / 失败切换）
- 翻译并发可配置
- 免 Key 翻译：MyMemory；Google 可不填 Key
- TTS 语速设置（0.5×～2.0×），默认 1.2×
- 刷新进度条（n/m · 源名）与动画优化

### Changed
- 优化默认翻译 / 摘要 / 解释 AI Prompt，并自动迁移旧默认模板

---

## [v1.3-21] — 2026-09-09

成功构建：`v1.3-21-build-20260909121250`  
相对：更早成功构建

### Added
- 收藏阅读页左滑下一篇收藏
- 评论：Hacker News（`<comments>` + Algolia）；Engadget 等 OpenWeb/Spot.IM
- 6 套阅读主题（Classic / Sepia / Night / Midnight / Forest / High Contrast）
- 设置：翻译目标语言、AI 输出语言
- 订阅源自动排序；阅读页下滑隐藏导航栏与 TabBar

### Fixed
- 少数派 / Foreign Policy / Foreign Affairs 全文与图片
- 开启自动翻译的源：进入列表/阅读页自动译未译内容
- 自动翻译跳过已隐藏文章；强化 HTML 去标签
- 刷新失败提示具体源名；HTTP 源 ATS；双重 Progress 转圈

### Security
- API Key 使用系统钥匙串；导出默认不含 Key；拦截私网 URL

### Changed
- 设置页层级重组；UI/UX 空状态与错误提示
- AI 测试改为针对单个 Provider

---

## [v1.3-1] — 2026-09-08

### Changed
- 版本线升至 1.3；主题、手势阅读、设置备份、Edge TTS 等里程碑能力汇总见 README

---

## [v1.2-5] — 2026-09-07

### Added
- Edge TTS、文章黑名单、源级自动翻译、图标一次获取标记等（详见该阶段提交）

---

更早版本摘要见仓库历史提交与 README「实现对照」表。
