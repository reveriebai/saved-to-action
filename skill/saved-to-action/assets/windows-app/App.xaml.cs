using System.Drawing;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace SavedToAction.Windows;

public partial class App : System.Windows.Application
{
    private readonly ActionStore _store = new();
    private DesktopCardWindow? _card;
    private BoardWindow? _board;
    private Forms.NotifyIcon? _tray;
    private DispatcherTimer? _timer;
    private bool _quitting;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _card = new DesktopCardWindow(_store, ShowBoard, () => _quitting);
        _card.Show();
        PositionCard();
        CreateTray();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _timer.Tick += (_, _) => RefreshAll();
        _timer.Start();
    }

    public void RefreshAll()
    {
        _card?.PushPayload();
        _board?.PushPayload();
    }

    private void ShowBoard()
    {
        _board ??= new BoardWindow(_store, RefreshAll, () => _quitting);
        _board.Show();
        _board.WindowState = WindowState.Normal;
        _board.Activate();
        _board.PushPayload();
    }

    private void PositionCard()
    {
        if (_card is null) return;
        var area = SystemParameters.WorkArea;
        _card.Left = area.Right - _card.Width - 28;
        _card.Top = area.Top + 28;
    }

    private void CreateTray()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("显示或隐藏桌面卡片", null, (_, _) =>
            {
                if (_card is null) return;
                if (_card.IsVisible) _card.Hide(); else { _card.Show(); PositionCard(); _card.Activate(); }
            });
        menu.Items.Add("打开完整看板", null, (_, _) => ShowBoard());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出 Saved to Action", null, (_, _) => Quit());

        _tray = new Forms.NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Saved to Action",
            Visible = true,
            ContextMenuStrip = menu
        };
        _tray.DoubleClick += (_, _) => ShowBoard();
    }

    private void Quit()
    {
        _quitting = true;
        _timer?.Stop();
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        _board?.Close();
        _card?.Close();
        Shutdown();
    }
}
