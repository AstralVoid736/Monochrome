using System;
using System.Runtime.InteropServices;

internal sealed class WindowsMagnifier : IDisplay, IDisposable
{
    private bool active = true;
    private WindowsMagnifier() { }

    public static WindowsMagnifier? Open() => MagInitialize() ? new WindowsMagnifier() : null;
    public bool TryGet(out Effect effect)
    {
        if (active) return MagGetFullscreenColorEffect(out effect);
        effect = default;
        return false;
    }
    public bool TrySet(Effect effect) => active && MagSetFullscreenColorEffect(in effect);
    public void Dispose()
    {
        if (!active) return;
        active = false;
        MagUninitialize();
    }

    private const string Library = "Magnification.dll";
    [DllImport(Library, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MagInitialize();

    [DllImport(Library, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MagUninitialize();

    [DllImport(Library, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MagGetFullscreenColorEffect(out Effect effect);

    [DllImport(Library, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MagSetFullscreenColorEffect(in Effect effect);
}
