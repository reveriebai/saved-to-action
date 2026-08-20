using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace SavedToAction.Windows;

internal static class NativeWindow
{
    private const int DwmWindowCornerPreference = 33;
    private const int Round = 2;

    public static void PreferRoundedCorners(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        var preference = Round;
        _ = DwmSetWindowAttribute(handle, DwmWindowCornerPreference, ref preference, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
