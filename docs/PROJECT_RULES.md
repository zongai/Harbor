# Harbor 项目默认规则（跨对话 / 构建约定）

本文件是 Grok 与协作者在本仓库上的**默认行为约定**。有冲突时以本文件与当前分支代码为准；无需用户每次提醒。

更新日期：2026-11-06

---

## 1. 仓库与分支

- GitHub 仓库：`zongai/Harbor`（原 `zongai/IosRss` 已重定向）。远程默认 `https://github.com/zongai/Harbor.git`。
- 新对话开始：先确认当前开发分支（`git branch --show-current` / `status`），**不要默认 main**。
- 当前主要功能分支（以实际 `git` 状态为准）：`feature/epub-opds`（EPUB / OPDS + 设置重构等）。
- 默认同步方式：**本地 git commit + `git push origin <branch>`**（不用 GitHub API `push_files` 回写代码）。
- GitHub PAT：从 `artifacts/.grok/secrets/github_token` 读取；未声明过期前复用，不要反复索要。

---

## 2. 构建与版本

- **每次正式构建前**：全面审查安全问题、明显 bug、不合理代码；先自动修复，再 tag / 推送触发 CI。
- 构建默认：升 `CURRENT_PROJECT_VERSION`；同步更新 `README.md` 与当前功能一致；`CHANGELOG` 按「**两次成功构建之间**」汇总（上一成功标签 → 本成功标签），不按中间未构建号拆条。
- CI **不**回写 docs / README / CHANGELOG。
- 触发构建：打并推送 `v*` 标签（见 `.github/workflows/build.yml`）；或 `workflow_dispatch`。
- 触发后：**轮询 GitHub Actions 至完成**，默认向用户报告成功/失败与 Release / IPA 链接。
- **构建成功后默认必须更新 SideStore**（见 §3）——用户无需再提醒。
- CI 注入：`AppVersion.githubBuildNumber` 由 CI `sed` 写入 run_number；设置页展示 `v1.3-{build}-buildN`。
- IPA 命名：`Harbor-{MARKETING}-{BUILD}-build{N}[-main].ipa`。

---

## 3. SideStore 源（构建成功后默认更新）

**硬性默认：CI 正式 IPA 构建 success → 立刻更新 `sidestore-apps.json` 并 push → 自动触发重建。用户不必再说「更新 sidestore」。**

- 仓库根目录：`sidestore-apps.json`（Harbor 单应用条目）。
- 工作流：`.github/workflows/rebuild-sidestore.yml`
  - **触发条件**：任意分支上 **push 且变更路径包含 `sidestore-apps.json`**。
  - **动作**：用 secret `SIDESTORE_REBUILD_TOKEN` 对 `https://sidestore.zongai.mom/admin/rebuild` 发 `POST`。
- **默认流程（每次成功出包后，不可省略）**：
  1. 轮询确认 Build Unsigned IPA **success**，记下 `MARKETING` / `BUILD` / `run_number` / IPA 文件名与 `size`；
  2. 改写 `sidestore-apps.json` 与最新 IPA 一致（见下）；
  3. `git commit` + `git push` 当前开发分支 → 自动跑 `Rebuild SideStore Source`；
  4. 轮询该 workflow 至完成；失败则查 token / 服务端并重试，不要只报「构建成功」却漏源。
- 字段映射：
  - `file` = Release 资源名全文（含 `-main` 等后缀）
  - `version` = `{MARKETING}.{BUILD}`（如 `1.3.129`）
  - `versionDate` = 发布日 `YYYY-MM-DD`
  - `versionDescription` = 本批 CHANGELOG 用户可见摘要（一两句）
  - `size` = IPA 字节数（Release asset `size`）
- 固定字段（勿随意改坏源）：
  - `bundleIdentifier`: `com.example.Harbor`
  - `name`: `Harbor`
  - `developerName`: `zongai`
  - `iconURL`: `https://raw.githubusercontent.com/zongai/zoo/refs/heads/main/Harbor.png`
  - `banner`: `https://raw.githubusercontent.com/zongai/zoo/refs/heads/main/banner.png`
  - `tintColor`: `3478F6`
  - `minOSVersion`: `17.0`（或与工程部署目标一致时再改）
- 仅当构建 **失败** 时不要改 sidestore。

---

## 4. SwiftUI / 代码风格

- 默认遵循 **SwiftUI Pro**：现代 API、可访问性、数据流、性能。
- 可点控件优先 `Button` / `Menu` + 文本标签 + `labelStyle(.iconOnly)`；避免裸 `onTapGesture` 做主交互。
- `foregroundStyle`；工具栏 `topBarTrailing`；大视图拆分子视图。
- 新改代码默认套用，无需用户再提醒。

---

## 5. 产品与实现惯例（摘要）

- 品牌：Harbor（观澜）；Bundle ID `com.example.Harbor`；缓存 / Keychain / iCloud 前缀 `harbor.*`。
- 设置导出：纳入可读偏好（含书籍排版、翻页方式等）；密钥默认不导出。
- 构建审查范围：编译风险、MainActor / 并发隔离、明显逻辑错误、敏感信息泄漏。

---

## 6. 本文件维护

- 新增「默认即执行、跨对话仍成立」的约定时：**更新本文件**，并写入项目记忆（`edit_memory`）。
- 一次性任务、临时调试步骤不要写入本文件。
