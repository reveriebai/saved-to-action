using Microsoft.Win32.SafeHandles;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace SavedToAction.Windows;

public static class SafeSourceResolver
{
    private const uint ShareAll = 0x00000001 | 0x00000002 | 0x00000004;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;

    public static string? ResolveLocalFile(string sourceRoot, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(sourceRoot) || string.IsNullOrWhiteSpace(relativePath)) return null;
        if (!Directory.Exists(sourceRoot)) return null;

        var candidate = Path.GetFullPath(Path.Combine(sourceRoot, relativePath));
        if (!File.Exists(candidate)) return null;

        try
        {
            var rootFinal = GetFinalPath(sourceRoot, directory: true);
            var candidateFinal = GetFinalPath(candidate, directory: false);
            return IsInside(candidateFinal, rootFinal) ? candidateFinal : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (Win32Exception)
        {
            return null;
        }
    }

    public static Uri? ResolveHttps(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return null;
        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)) return null;
        if (string.IsNullOrWhiteSpace(uri.Host) || !string.IsNullOrEmpty(uri.UserInfo)) return null;
        return uri;
    }

    public static bool IsInside(string candidate, string root)
    {
        var relative = Path.GetRelativePath(root, candidate);
        return relative == "." ||
               (!Path.IsPathRooted(relative) &&
                !relative.Equals("..", StringComparison.Ordinal) &&
                !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal));
    }

    private static string GetFinalPath(string path, bool directory)
    {
        using var handle = CreateFileW(
            path,
            0,
            ShareAll,
            IntPtr.Zero,
            OpenExisting,
            directory ? BackupSemantics : 0,
            IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());

        var capacity = 512;
        while (true)
        {
            var buffer = new StringBuilder(capacity);
            var length = GetFinalPathNameByHandleW(handle, buffer, (uint)capacity, 0);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (length < capacity) return NormalizeFinalPath(buffer.ToString());
            capacity = checked((int)length + 1);
        }
    }

    private static string NormalizeFinalPath(string path)
    {
        if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
            return @"\\" + path[8..].TrimEnd(Path.DirectorySeparatorChar);
        if (path.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
            return path[4..].TrimEnd(Path.DirectorySeparatorChar);
        return path.TrimEnd(Path.DirectorySeparatorChar);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle file,
        StringBuilder filePath,
        uint filePathSize,
        uint flags);
}
