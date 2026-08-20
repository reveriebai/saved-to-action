using System.Windows;

namespace SavedToAction.Windows;

public sealed class BoardWindow : WebViewHostWindow
{
    private readonly Action _refresh;

    public BoardWindow(ActionStore store, Action refresh, Func<bool> isQuitting)
        : base(store, "Board.html", isQuitting)
    {
        _refresh = refresh;
        Title = "收藏行动看板";
        Width = 1180;
        Height = 820;
        MinWidth = 840;
        MinHeight = 620;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
    }

    protected override void Changed() => _refresh();
}
