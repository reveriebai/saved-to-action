using System.Text.Json;
using System.Windows;
using System.Windows.Input;

namespace SavedToAction.Windows;

public sealed class DesktopCardWindow : WebViewHostWindow
{
    private readonly Action _showBoard;

    public DesktopCardWindow(ActionStore store, Action showBoard, Func<bool> isQuitting)
        : base(store, "DesktopCard.html", isQuitting)
    {
        _showBoard = showBoard;
        Title = "Saved to Action";
        Width = 454;
        Height = 514;
        MinWidth = 390;
        MinHeight = 440;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.CanResizeWithGrip;
        ShowInTaskbar = false;
        Topmost = false;
    }

    protected override void HandleMessage(string name, JsonElement payload)
    {
        var id = payload.ValueKind == JsonValueKind.String ? payload.GetString() ?? "" : "";
        switch (name)
        {
            case "beginDrag":
                if (Mouse.LeftButton == MouseButtonState.Pressed)
                {
                    try { DragMove(); } catch (InvalidOperationException) { }
                }
                return;
            case "openBoard":
                _showBoard();
                return;
            case "next":
                Store.Advance();
                Changed();
                return;
            case "complete":
                Store.Complete(id);
                Store.Advance();
                Changed();
                return;
            case "burn":
                Store.Burn(id);
                Store.Advance();
                Changed();
                return;
            case "toggleTracked":
                Store.ToggleTracked(id);
                Changed();
                return;
            default:
                base.HandleMessage(name, payload);
                return;
        }
    }

    protected override void Changed() => ((App)System.Windows.Application.Current).RefreshAll();
}
