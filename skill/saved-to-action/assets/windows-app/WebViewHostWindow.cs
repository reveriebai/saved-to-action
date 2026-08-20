using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace SavedToAction.Windows;

public abstract class WebViewHostWindow : Window
{
    protected readonly ActionStore Store;
    protected readonly WebView2 WebView = new();
    private readonly string _resourceName;
    private readonly Func<bool> _isQuitting;
    private bool _ready;

    protected WebViewHostWindow(ActionStore store, string resourceName, Func<bool> isQuitting)
    {
        Store = store;
        _resourceName = resourceName;
        _isQuitting = isQuitting;
        Background = new SolidColorBrush(Color.FromRgb(239, 226, 208));
        Content = WebView;
        Loaded += OnLoaded;
        Closing += OnClosing;
    }

    public async void PushPayload()
    {
        if (!_ready || WebView.CoreWebView2 is null) return;
        var payload = Store.PayloadBase64().Replace("\\", "\\\\").Replace("'", "\\'");
        try
        {
            await WebView.CoreWebView2.ExecuteScriptAsync($"window.applyNativePayloadBase64?.('{payload}');");
        }
        catch (InvalidOperationException)
        {
            _ready = false;
        }
    }

    protected virtual void HandleMessage(string name, JsonElement payload)
    {
        switch (name)
        {
            case "boardStateDidChange":
                Store.ImportState(payload.ValueKind == JsonValueKind.String ? payload.GetString() ?? "{}" : payload.GetRawText());
                Changed();
                break;
            case "openSource":
                if (payload.ValueKind == JsonValueKind.String) Store.OpenSource(payload.GetString() ?? "");
                break;
            case "openRevisit":
                Store.OpenRevisit();
                break;
            case "convertRevisit":
                Store.ConvertRevisit();
                Changed();
                break;
        }
    }

    protected abstract void Changed();

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        NativeWindow.PreferRoundedCorners(this);
        await WebView.EnsureCoreWebView2Async();
        WebView.CoreWebView2.Settings.AreDevToolsEnabled = false;
        WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        WebView.CoreWebView2.WebMessageReceived += OnWebMessage;
        WebView.CoreWebView2.NavigationStarting += (_, args) =>
        {
            if (Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) && uri.Scheme != Uri.UriSchemeFile)
            {
                args.Cancel = true;
                if (uri.Scheme == Uri.UriSchemeHttps)
                    Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
            }
        };
        var file = Path.Combine(AppContext.BaseDirectory, "Resources", _resourceName);
        WebView.NavigationCompleted += (_, _) => { _ready = true; PushPayload(); };
        WebView.Source = new Uri(file);
    }

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var document = JsonDocument.Parse(e.WebMessageAsJson);
            var root = document.RootElement;
            if (!root.TryGetProperty("name", out var nameElement) || nameElement.ValueKind != JsonValueKind.String) return;
            root.TryGetProperty("payload", out var payload);
            HandleMessage(nameElement.GetString() ?? "", payload);
        }
        catch (JsonException)
        {
            // Ignore malformed messages from the bundled page.
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_isQuitting()) return;
        e.Cancel = true;
        Hide();
    }
}
