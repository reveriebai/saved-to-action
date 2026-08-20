# Saved to Action

把散落在本机 Markdown 文件夹里的“以后再看”，变成真正能开始的下一步。

Saved to Action 是一个独立 Codex skill，配套一款本地 macOS 桌面卡片。它只读扫描你指定的 Markdown，利用当前对话中的 AI 为每篇新笔记提炼 1–2 个具体行动，再由确定性脚本校验并原子写入本地 JSON。完成、追踪和阅后即焚状态只保存在本机。

> 当前仓库处于私有验收阶段。转为公开后，其他用户才能直接从 GitHub 安装。

## 它会做什么

- 支持一个或多个任意 Markdown 文件夹，不要求 Obsidian 或特定同步服务。
- 优先使用 frontmatter 的 `uid` / `id`；缺失时使用来源名称与相对路径哈希。
- 每篇新笔记生成 1–2 张可以在 10–30 分钟内开始的行动卡。
- 提供桌面悬浮卡、菜单栏入口和复古编辑部风格完整看板。
- 可手动增量运行，也可在首次验证后由 Codex 创建定时任务。

## 隐私边界

- 来源 Markdown 永远只读，不补写 frontmatter，不移动、不重命名。
- 笔记正文、代码块和链接都被视为不可信数据，不会自动执行。
- 工作区配置、行动 JSON、App 状态和绝对路径都不上传到仓库。
- App 打开原文前会再次确认文件仍位于配置的来源目录内。
- 项目不需要 OpenAI API Key；行动文字由你正在使用的 Codex/ChatGPT 会话生成。

## 环境要求

- macOS 13 或更高版本。
- Python 3。
- Apple Command Line Tools，可通过 `xcrun --show-sdk-path` 检查。
- Codex CLI、IDE 扩展或 ChatGPT 桌面端。只有桌面端提供定时任务管理界面。

## 安装 skill

转为公开仓库后，可直接告诉 Codex：

```text
请用 $skill-installer 从 mining2277-hub/saved-to-action 的 skill/saved-to-action 安装 skill。
```

也可以使用系统自带安装器：

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo mining2277-hub/saved-to-action \
  --path skill/saved-to-action
```

私有仓库阶段需要本机已有可访问该仓库的 Git 凭据。

## 第一次使用

显式调用 skill，并给出来源目录：

```text
用 $saved-to-action 先只读检查“/绝对路径/我的笔记”，确认后再帮我建立行动看板。
```

Skill 会先报告笔记数量、身份识别方式和示例，再让你选择：

- 仅处理以后新增：当前内容全部作为基线。
- 最近 N 篇：只把最近 N 篇留作首次行动提炼。
- 全部处理：为所有现有 Markdown 提炼行动。

确认后才会创建工作区。默认分类为：工作与项目、学习与研究、创作与表达、健康与生活、工具与系统、待分类。

“最近”优先依据 frontmatter 的 `created` / `date`；缺失时回退到文件创建时间（平台不提供时使用修改时间）。

## 手动增量同步

```text
用 $saved-to-action 同步“/绝对路径/工作区”里的新增笔记；先给我看候选行动，确认后再写入。
```

每次成功同步都会经过：验证旧数据 → 发现新笔记 → 提炼候选 → 校验整批数据 → 原子替换 → 再验证。

## 构建 macOS App

```text
用 $saved-to-action 为“/绝对路径/工作区”构建 macOS 看板，先不要安装。
```

默认产物位于工作区 `dist/Saved to Action.app`。确认体验后，再让 skill 安装到 `~/Applications` 并写入本机 App 配置。首版使用 ad-hoc 签名，不提供未经 Developer ID 签名与公证的预编译下载。

## 定时运行

先手动跑通一次同步并打开 App，再告诉 Codex 具体时间：

```text
用 $saved-to-action 为这个工作区创建一个每天早上 8:30 的独立定时任务，只处理新增 Markdown。
```

依赖本机文件的定时任务需要电脑保持开机、桌面 App 运行且工作目录仍可访问。CLI 和 IDE 扩展用户可以继续手动运行同步。

## 卸载

1. 在 Skills 中禁用或删除 `saved-to-action`。
2. 退出并移除 `~/Applications/Saved to Action.app`（如果安装过）。
3. 确认不再需要行动历史后，再删除你自己选择的工作目录。
4. 如创建过定时任务，在桌面端 Scheduled 中暂停或删除。

卸载不会改动任何来源 Markdown。

## 开发与验证

```bash
python3 -m unittest discover -s tests -v
python3 skill/saved-to-action/scripts/privacy_scan.py .
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py skill/saved-to-action
```

macOS App 由 skill 中的构建脚本按当前机器架构编译。CI 会运行 Python 测试、原生 App 集成测试、skill 结构检查、隐私扫描和 App 编译。

## License

MIT
