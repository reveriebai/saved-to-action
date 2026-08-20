# 数据契约

## 工作区配置 `saved-to-action.json`

- `version`: 固定为 `1`。
- `language`: 首版为 `zh-CN`。
- `recursive`: 是否递归扫描来源目录。
- `include` / `exclude`: 针对来源内相对路径的 glob 数组。
- `identityKeys`: frontmatter 身份字段优先级，默认 `uid`、`id`。
- `categories`: 允许写入行动卡的分类白名单。
- `sources`: `{name, path}` 数组；名称唯一，路径为本机绝对目录。
- `dataPath`: 相对工作区的数据路径，必须留在工作区内。

不要把配置文件提交到公开仓库；它包含用户的本机路径。

## 笔记身份

1. 使用第一个非空的 frontmatter `uid` 或 `id`。
2. 没有身份字段时，使用 `SHA-256("path\0来源名称\0相对路径")`。
3. 对外只保存哈希后的 `sourceId`，不把原始 uid 写入行动 ID。
4. 路径回退笔记改名后会得到新身份；这是首版明确行为。
5. 两个文件解析为同一个身份时中止整次扫描，不猜测、不去重。

## 行动数据 `Data/actions.json`

顶层字段为 `version`、`updatedAt`、`processedNotes`、`actions`。

`processedNotes` 每项包含：

- `sourceId`、`sourceName`、`relativePath`、`title`
- `processedAt`
- `mode`: `baseline` 或 `incremental`
- `actionIds`: 基线为空；增量严格为 1–2 个 ID

`actions` 每项包含：

- `id`: 脚本按 sourceId 哈希和序号生成
- `sourceId`、`sourceName`、`relativePath`
- `collectionTitle`、`category`、`intent`、`task`
- `detail`: 字符串或 `null`
- `savedAt`: `YYYY-MM-DD`
- `sourceType`: `Markdown 笔记`

`savedAt` 优先读取 frontmatter 的 `created`、其次 `date`；无法解析时使用文件创建时间（平台不提供时使用修改时间）。“最近 N 篇”按 `savedAt`、文件修改时间、相对路径依次排序后取末尾 N 篇。

提交必须一次验证整个候选数据后原子替换。任何失败都不能追加 processedNotes。

## App 状态

完成、追踪、焚毁和当前行动使用 UserDefaults 键 `saved-to-action-state-v1`。同步脚本不读取、不修改、不重建该状态。
