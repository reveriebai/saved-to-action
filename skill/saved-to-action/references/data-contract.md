# 数据契约

## 工作区配置 `saved-to-action.json`

- `version`: 固定为 `1`。
- `language`: 首版为 `zh-CN`。
- `recursive`: 是否递归扫描来源目录。
- `include` / `exclude`: 针对来源内相对路径的 glob 数组。
- `identityKeys`: frontmatter 身份字段优先级，默认 `uid`、`id`。
- `categories`: 允许写入行动卡的分类白名单。
- `sources`: 名称唯一的来源数组：
  - Markdown：`{name, kind: "markdown", path}`；旧配置省略 `kind` 时仍按 Markdown 处理。
  - Get笔记全部：`{name, kind: "getnote"}`；指定知识库时增加 `topicId`。
  - IMA：`{name, kind: "ima", knowledgeBaseId}`。
- `dataPath`: 相对工作区的数据路径，必须留在工作区内。

不要把配置文件提交到公开仓库；它包含用户的本机路径。

## 来源身份

1. 使用第一个非空的 frontmatter `uid` 或 `id`。
2. 没有身份字段时，使用 `SHA-256("path\0来源名称\0相对路径")`。
3. 对外只保存哈希后的 `sourceId`，不把原始 uid 写入行动 ID。
4. 路径回退笔记改名后会得到新身份；这是首版明确行为。
5. 两个文件解析为同一个身份时中止整次扫描，不猜测、不去重。
6. Get笔记使用来源名称、适配器类型和稳定 note ID 哈希；IMA 使用来源名称、适配器类型和稳定 media ID 哈希。
7. 原始外部 ID 只存在本地来源定位中，不进入行动 ID，也不得写进公开仓库样例。

## 行动数据 `Data/actions.json`

顶层字段为 `version`、`updatedAt`、`processedNotes`、`actions`、`dailyRevisit`、`revisitHistory`。

`processedNotes` 每项包含：

- `sourceId`、`sourceName`、`relativePath`、`title`
- `processedAt`
- `mode`: `baseline` 或 `incremental`
- `actionIds`: 基线为空；增量严格为 1–2 个 ID
- 新建工作区的记录还保存 `savedAt` 与 `sourceType`，用于在 IMA 后续扫描缺少收藏时间时保持首次日期；旧版记录缺失这两个字段仍可读取

`actions` 每项包含：

- `id`: 脚本按 sourceId 哈希和序号生成
- `sourceId`、`sourceName`、`relativePath`
- `collectionTitle`、`category`、`intent`、`task`
- `detail`: 字符串或 `null`
- `savedAt`: `YYYY-MM-DD`
- `sourceType`: 例如 `Markdown 笔记`、`Get笔记网页收藏`、`IMA 原生笔记`、`IMA 公众号文章`
- `sourceURL`: 安全、稳定的 HTTPS 原文地址或 `null`；不得保存 IMA/COS 临时签名和微信会话参数

Markdown 的 `savedAt` 优先读取 frontmatter 的 `created`、其次 `date`；Get笔记使用创建时间。IMA 列表没有收藏时间时使用首次扫描日期并保留接口顺序。“最近 N 篇”按 `savedAt`、来源顺序/修改时间、相对路径依次排序后取末尾 N 篇。

提交必须一次验证整个候选数据后原子替换。任何失败都不能追加 processedNotes。

## 每日旧收藏回看

`dailyRevisit` 为 `null` 或包含：`sourceId`、`sourceName`、`relativePath`、`title`、`summary`、`usage`、`task`、可空 `detail`、`savedAt`、`selectedAt`、可空 `sourceURL`。

- 只能引用 `processedNotes.actionIds` 为空且来源仍可发现的笔记。
- `revisitHistory` 保存已展示过的 sourceId，用于优先未展示内容；不作为处理状态。
- 每天最多更新一次；存在多个候选时不连续重复同一篇。
- 看板转换的回看行动只进入 UserDefaults，不写回本文件。

## App 状态

完成、追踪、焚毁、当前行动和由回看转换的本地行动使用 UserDefaults 键 `saved-to-action-state-v1`。同步脚本不读取、不修改、不重建该状态。回看转换为本地行动时保留经过验证的 `sourceURL`，不刷新或写回来源。
