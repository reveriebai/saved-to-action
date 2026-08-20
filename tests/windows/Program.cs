using SavedToAction.Windows;
using System.Text.Json;

var root = Path.Combine(Path.GetTempPath(), "saved-to-action-windows-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    var notes = Path.Combine(root, "notes");
    var workspace = Path.Combine(root, "workspace");
    Directory.CreateDirectory(notes);
    Directory.CreateDirectory(workspace);
    File.WriteAllText(Path.Combine(notes, "example.md"), "# 示例");

    var configPath = Path.Combine(workspace, "saved-to-action.config.json");
    var dataPath = Path.Combine(workspace, "saved-to-action.json");
    var pointerPath = Path.Combine(root, "app.json");
    var statePath = Path.Combine(root, "state.json");

    Write(configPath, new
    {
        version = 1,
        sources = new[] { new { name = "示例", kind = "markdown", path = notes } },
        dataPath = "saved-to-action.json"
    });
    Write(dataPath, new
    {
        version = 1,
        actions = new[]
        {
            new
            {
                id = "action-1", sourceId = "source-1", sourceName = "示例", relativePath = "example.md",
                collectionTitle = "虚构收藏", category = "学习与研究", intent = "理解一个概念", task = "写下一个例子",
                detail = (string?)null, savedAt = "2026-08-01", sourceType = "Markdown", sourceURL = (string?)null
            }
        },
        dailyRevisit = new
        {
            sourceId = "old-source", sourceName = "示例", relativePath = "example.md", title = "旧收藏",
            summary = "重新看看旧内容", usage = "需要一个新点子时", task = "写下一条可复用观点", detail = (string?)null,
            savedAt = "2026-07-01", selectedAt = "2026-08-20", sourceURL = (string?)null
        }
    });
    Write(pointerPath, new { version = 1, workspaceConfigPath = configPath });

    var store = new ActionStore(pointerPath, statePath, () => new DateTime(2026, 8, 20));
    var payload = store.LoadPayload();
    Require(payload.Configured, "fixture should be configured");
    Require(payload.Actions.Count == 1 && payload.Actions[0].HasSource, "local source should resolve inside configured root");
    Require(payload.DailyRevisit is not null && payload.DailyRevisit.HasSource, "daily revisit source should resolve");

    store.ToggleTracked("action-1");
    store.Complete("action-1");
    var completed = store.LoadState();
    Require(completed.Done.SequenceEqual(["action-1"]), "completed action should persist");
    Require(!completed.Tracked.Contains("action-1") && !completed.Burned.Contains("action-1"), "completed state must not leak into tracked or burned");

    store.Burn("action-1");
    var burned = store.LoadState();
    Require(burned.Burned.SequenceEqual(["action-1"]), "burned action should persist");
    Require(!burned.Done.Contains("action-1") && !burned.Tracked.Contains("action-1"), "burned state must be mutually exclusive");

    var revisitId = store.ConvertRevisit();
    Require(revisitId is not null && store.LoadState().Custom.Any(item => item.Id == revisitId), "revisit conversion should remain local state");
    store.ConvertRevisit();
    Require(store.LoadState().Custom.Count(item => item.Id == revisitId) == 1, "revisit conversion must be idempotent");

    File.WriteAllText(dataPath, "{broken");
    var degraded = store.LoadPayload();
    Require(!degraded.Configured && degraded.Message.Contains("损坏"), "corrupt data should degrade without overwriting source");
    Require(File.ReadAllText(dataPath) == "{broken", "app must not rewrite corrupt action data");

    Require(!SafeSourceResolver.IsInside(Path.Combine(root, "outside.md"), notes), "lexical path boundary should reject siblings");
    Console.WriteLine("Windows integration harness passed.");
}
finally
{
    Directory.Delete(root, recursive: true);
}

static void Write(string path, object value)
{
    File.WriteAllText(path, JsonSerializer.Serialize(value, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
