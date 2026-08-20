using System.Text.Json.Serialization;

namespace SavedToAction.Windows;

public sealed class AppPointer
{
    public int Version { get; set; }
    public string WorkspaceConfigPath { get; set; } = "";
}

public sealed class WorkspaceConfig
{
    public int Version { get; set; }
    public List<SourceConfig> Sources { get; set; } = [];
    public string DataPath { get; set; } = "saved-to-action.json";
}

public sealed class SourceConfig
{
    public string Name { get; set; } = "";
    public string? Kind { get; set; }
    public string? Path { get; set; }
}

public sealed class ActionFile
{
    public int Version { get; set; }
    public List<StoredAction> Actions { get; set; } = [];
    public StoredRevisit? DailyRevisit { get; set; }
}

public sealed class StoredAction
{
    public string Id { get; set; } = "";
    public string SourceId { get; set; } = "";
    public string SourceName { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public string CollectionTitle { get; set; } = "";
    public string Category { get; set; } = "待分类";
    public string Intent { get; set; } = "";
    public string Task { get; set; } = "";
    public string? Detail { get; set; }
    public string SavedAt { get; set; } = "";
    public string SourceType { get; set; } = "";
    public string? SourceURL { get; set; }
}

public sealed class StoredRevisit
{
    public string SourceId { get; set; } = "";
    public string SourceName { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public string Title { get; set; } = "";
    public string Summary { get; set; } = "";
    public string Usage { get; set; } = "";
    public string Task { get; set; } = "";
    public string? Detail { get; set; }
    public string SavedAt { get; set; } = "";
    public string SelectedAt { get; set; } = "";
    public string? SourceURL { get; set; }
}

public sealed class LocalAction
{
    public string Id { get; set; } = "";
    public string SourceId { get; set; } = "";
    public string SourceName { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public string Title { get; set; } = "";
    public string Task { get; set; } = "";
    public string Intent { get; set; } = "";
    public string? Detail { get; set; }
    public string SavedAt { get; set; } = "";
    public string? SourceURL { get; set; }
}

public sealed class BoardState
{
    public List<string> Done { get; set; } = [];
    public List<string> Tracked { get; set; } = [];
    public List<string> Burned { get; set; } = [];
    public string? CurrentAction { get; set; }
    public List<LocalAction> Custom { get; set; } = [];
}

public sealed class BoardAction
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Category { get; set; } = "待分类";
    public string Intent { get; set; } = "";
    public string Task { get; set; } = "";
    public string? Detail { get; set; }
    public int SavedDays { get; set; }
    public string SourceName { get; set; } = "";
    public string SourceType { get; set; } = "";
    public bool HasSource { get; set; }
}

public sealed class BoardRevisit
{
    public string SourceId { get; set; } = "";
    public string Title { get; set; } = "";
    public string Summary { get; set; } = "";
    public string Usage { get; set; } = "";
    public string Task { get; set; } = "";
    public string? Detail { get; set; }
    public int SavedDays { get; set; }
    public string SelectedAt { get; set; } = "";
    public bool HasSource { get; set; }
    public bool Converted { get; set; }
}

public sealed class BoardPayload
{
    public bool Configured { get; set; }
    public string Message { get; set; } = "";
    public BoardState State { get; set; } = new();
    public List<BoardAction> Actions { get; set; } = [];
    public BoardRevisit? DailyRevisit { get; set; }
}
