using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace SavedToAction.Windows;

public sealed class ActionStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly string _pointerPath;
    private readonly string _statePath;
    private readonly Func<DateTime> _now;

    public ActionStore(string? pointerPath = null, string? statePath = null, Func<DateTime>? now = null)
    {
        _pointerPath = pointerPath ?? DefaultPointerPath();
        _statePath = statePath ?? DefaultStatePath();
        _now = now ?? (() => DateTime.Now);
    }

    public BoardState LoadState()
    {
        try
        {
            if (!File.Exists(_statePath)) return new BoardState();
            return JsonSerializer.Deserialize<BoardState>(File.ReadAllText(_statePath), JsonOptions) ?? new BoardState();
        }
        catch (JsonException)
        {
            return new BoardState();
        }
        catch (IOException)
        {
            return new BoardState();
        }
    }

    public void SaveState(BoardState state)
    {
        var directory = Path.GetDirectoryName(_statePath) ?? throw new InvalidOperationException("状态路径缺少父目录。");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".{Path.GetFileName(_statePath)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(state, JsonOptions), new UTF8Encoding(false));
            File.Move(temporary, _statePath, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public void ImportState(string json)
    {
        var state = JsonSerializer.Deserialize<BoardState>(json, JsonOptions);
        if (state is null) throw new JsonException("看板状态为空。");
        state.Done ??= [];
        state.Tracked ??= [];
        state.Burned ??= [];
        state.Custom ??= [];
        SaveState(state);
    }

    public BoardPayload LoadPayload()
    {
        var loaded = LoadEntries();
        var state = LoadState();
        var actions = loaded.Actions.Select(item => ToBoardAction(item.Action, item.Source)).ToList();
        actions.AddRange(state.Custom.Select(item => ToBoardAction(item, ResolveCustomSource(item, loaded.SourceRoots))));

        var revisitId = loaded.Revisit is null ? null : RevisitId(loaded.Revisit.Value.Revisit.SourceId);
        var revisit = loaded.Revisit is null ? null : new BoardRevisit
        {
            SourceId = loaded.Revisit.Value.Revisit.SourceId,
            Title = loaded.Revisit.Value.Revisit.Title,
            Summary = loaded.Revisit.Value.Revisit.Summary,
            Usage = loaded.Revisit.Value.Revisit.Usage,
            Task = loaded.Revisit.Value.Revisit.Task,
            Detail = loaded.Revisit.Value.Revisit.Detail,
            SavedDays = DaysSince(loaded.Revisit.Value.Revisit.SavedAt),
            SelectedAt = loaded.Revisit.Value.Revisit.SelectedAt,
            HasSource = loaded.Revisit.Value.Source is not null,
            Converted = revisitId is not null && state.Custom.Any(item => item.Id == revisitId)
        };

        return new BoardPayload
        {
            Configured = loaded.Configured,
            Message = actions.Count == 0 && string.IsNullOrEmpty(loaded.Message)
                ? "还没有行动卡。运行一次增量同步后，它们会出现在这里。"
                : loaded.Message,
            State = state,
            Actions = actions,
            DailyRevisit = revisit
        };
    }

    public string PayloadBase64()
    {
        var json = JsonSerializer.Serialize(LoadPayload(), JsonOptions);
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
    }

    public void Advance()
    {
        var payload = LoadPayload();
        var open = OpenActions(payload).ToList();
        if (open.Count == 0)
        {
            payload.State.CurrentAction = null;
            SaveState(payload.State);
            return;
        }
        var index = open.FindIndex(action => action.Id == payload.State.CurrentAction);
        payload.State.CurrentAction = open[(index + 1 + open.Count) % open.Count].Id;
        SaveState(payload.State);
    }

    public void Complete(string id)
    {
        var state = LoadState();
        AddUnique(state.Done, id);
        state.Tracked.RemoveAll(value => value == id);
        state.Burned.RemoveAll(value => value == id);
        if (state.CurrentAction == id) state.CurrentAction = null;
        SaveState(state);
    }

    public void Burn(string id)
    {
        var state = LoadState();
        AddUnique(state.Burned, id);
        state.Done.RemoveAll(value => value == id);
        state.Tracked.RemoveAll(value => value == id);
        if (state.CurrentAction == id) state.CurrentAction = null;
        SaveState(state);
    }

    public void ToggleTracked(string id)
    {
        var state = LoadState();
        if (state.Tracked.Contains(id)) state.Tracked.RemoveAll(value => value == id);
        else state.Tracked.Add(id);
        SaveState(state);
    }

    public void OpenSource(string id)
    {
        var loaded = LoadEntries();
        var entry = loaded.Actions.FirstOrDefault(item => item.Action.Id == id);
        Uri? source = entry?.Source;
        if (source is null)
        {
            var custom = LoadState().Custom.FirstOrDefault(item => item.Id == id);
            if (custom is not null) source = ResolveCustomSource(custom, loaded.SourceRoots);
        }
        Open(source);
    }

    public void OpenRevisit()
    {
        Open(LoadEntries().Revisit?.Source);
    }

    public string? ConvertRevisit()
    {
        var loaded = LoadEntries();
        if (loaded.Revisit is null) return null;
        var revisit = loaded.Revisit.Value.Revisit;
        var id = RevisitId(revisit.SourceId);
        var state = LoadState();
        if (state.Custom.All(item => item.Id != id))
        {
            state.Custom.Add(new LocalAction
            {
                Id = id,
                SourceId = revisit.SourceId,
                SourceName = revisit.SourceName,
                RelativePath = revisit.RelativePath,
                Title = revisit.Title,
                Task = revisit.Task,
                Intent = revisit.Summary,
                Detail = revisit.Detail,
                SavedAt = revisit.SavedAt,
                SourceURL = revisit.SourceURL
            });
        }
        state.CurrentAction = id;
        SaveState(state);
        return id;
    }

    private LoadedEntries LoadEntries()
    {
        try
        {
            if (!File.Exists(_pointerPath)) return LoadedEntries.Failure("尚未配置工作目录。请先构建或重新配置 Windows 看板。");
            var pointer = Read<AppPointer>(_pointerPath);
            if (pointer.Version != 1 || !File.Exists(pointer.WorkspaceConfigPath))
                return LoadedEntries.Failure("找不到工作目录配置，请确认目录仍然存在。");

            var workspacePath = Path.GetFullPath(pointer.WorkspaceConfigPath);
            var config = Read<WorkspaceConfig>(workspacePath);
            if (config.Version != 1) return LoadedEntries.Failure("工作目录配置无法解析。");

            var workspaceRoot = Path.GetDirectoryName(workspacePath)!;
            var dataPath = SafeSourceResolver.ResolveLocalFile(workspaceRoot, config.DataPath);
            if (dataPath is null)
                return LoadedEntries.Failure("行动数据不存在或超出工作目录。");

            var actionFile = Read<ActionFile>(dataPath);
            if (actionFile.Version != 1) return LoadedEntries.Failure("行动数据损坏；原文件没有被 App 修改。");

            var roots = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var source in config.Sources)
            {
                if (roots.ContainsKey(source.Name)) return LoadedEntries.Failure("工作目录包含重复的来源名称。");
                if (string.Equals(source.Kind ?? "markdown", "markdown", StringComparison.Ordinal) && source.Path is not null)
                    roots[source.Name] = source.Path;
            }

            var actions = actionFile.Actions
                .Select(action => new ActionEntry(action, ResolveSource(action.SourceURL, action.SourceName, action.RelativePath, roots)))
                .ToList();
            RevisitEntry? revisit = actionFile.DailyRevisit is null
                ? null
                : new RevisitEntry(actionFile.DailyRevisit, ResolveSource(actionFile.DailyRevisit.SourceURL, actionFile.DailyRevisit.SourceName, actionFile.DailyRevisit.RelativePath, roots));
            return new LoadedEntries(true, "", actions, revisit, roots);
        }
        catch (JsonException)
        {
            return LoadedEntries.Failure("行动数据或配置损坏；原文件没有被 App 修改。");
        }
        catch (IOException)
        {
            return LoadedEntries.Failure("无法读取行动数据，请确认工作目录仍然可访问。");
        }
        catch (UnauthorizedAccessException)
        {
            return LoadedEntries.Failure("没有读取工作目录的权限。");
        }
    }

    private T Read<T>(string path) where T : class
    {
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions)
               ?? throw new JsonException($"无法解析 {Path.GetFileName(path)}");
    }

    private Uri? ResolveSource(string? sourceUrl, string sourceName, string relativePath, IReadOnlyDictionary<string, string> roots)
    {
        var remote = SafeSourceResolver.ResolveHttps(sourceUrl);
        if (remote is not null) return remote;
        if (!roots.TryGetValue(sourceName, out var root)) return null;
        var local = SafeSourceResolver.ResolveLocalFile(root, relativePath);
        return local is null ? null : new Uri(local);
    }

    private Uri? ResolveCustomSource(LocalAction action, IReadOnlyDictionary<string, string> roots)
        => ResolveSource(action.SourceURL, action.SourceName, action.RelativePath, roots);

    private BoardAction ToBoardAction(StoredAction action, Uri? source) => new()
    {
        Id = action.Id,
        Title = action.CollectionTitle,
        Category = action.Category,
        Intent = action.Intent,
        Task = action.Task,
        Detail = action.Detail,
        SavedDays = DaysSince(action.SavedAt),
        SourceName = action.SourceName,
        SourceType = action.SourceType,
        HasSource = source is not null
    };

    private BoardAction ToBoardAction(LocalAction action, Uri? source) => new()
    {
        Id = action.Id,
        Title = action.Title,
        Category = "待分类",
        Intent = action.Intent,
        Task = action.Task,
        Detail = action.Detail,
        SavedDays = DaysSince(action.SavedAt),
        SourceName = action.SourceName,
        SourceType = "旧收藏回看",
        HasSource = source is not null
    };

    private int DaysSince(string value)
    {
        return DateTime.TryParseExact(value, "yyyy-MM-dd", null, System.Globalization.DateTimeStyles.None, out var saved)
            ? Math.Max(0, (_now().Date - saved.Date).Days)
            : 0;
    }

    private static IEnumerable<BoardAction> OpenActions(BoardPayload payload)
        => payload.Actions.Where(action => !payload.State.Done.Contains(action.Id) && !payload.State.Burned.Contains(action.Id));

    private static string RevisitId(string sourceId)
    {
        var suffix = sourceId.Length <= 24 ? sourceId : sourceId[^24..];
        return "revisit:" + suffix;
    }

    private static void AddUnique(List<string> values, string value)
    {
        if (!values.Contains(value)) values.Add(value);
    }

    private static void Open(Uri? source)
    {
        if (source is null) return;
        Process.Start(new ProcessStartInfo(source.IsFile ? source.LocalPath : source.AbsoluteUri) { UseShellExecute = true });
    }

    private static string DefaultPointerPath()
    {
        var overridePath = Environment.GetEnvironmentVariable("SAVED_TO_ACTION_APP_CONFIG");
        if (!string.IsNullOrWhiteSpace(overridePath)) return overridePath;
        var userPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SavedToAction", "app.json");
        return File.Exists(userPath) ? userPath : Path.Combine(AppContext.BaseDirectory, "AppConfig.json");
    }

    private static string DefaultStatePath()
    {
        var overridePath = Environment.GetEnvironmentVariable("SAVED_TO_ACTION_STATE_PATH");
        return !string.IsNullOrWhiteSpace(overridePath)
            ? overridePath
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SavedToAction", "saved-to-action-state-v1.json");
    }

    private sealed record ActionEntry(StoredAction Action, Uri? Source);
    private readonly record struct RevisitEntry(StoredRevisit Revisit, Uri? Source);
    private sealed record LoadedEntries(
        bool Configured,
        string Message,
        List<ActionEntry> Actions,
        RevisitEntry? Revisit,
        Dictionary<string, string> SourceRoots)
    {
        public static LoadedEntries Failure(string message) => new(false, message, [], null, new(StringComparer.Ordinal));
    }
}
