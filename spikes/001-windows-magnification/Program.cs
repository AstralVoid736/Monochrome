using System;
using System.Runtime.InteropServices;
using System.Threading;

internal static class Program
{
    private const int HoldMilliseconds = 1500;
    private static readonly ManualResetEventSlim Stop = new();

    private static int Main(string[] args)
    {
        var mode = args.Length == 0 ? "--check" : args[0];
        if (args.Length > 1 || mode is not ("--check" or "--flash" or "--restore-probe-matrix" or "--help"))
        {
            PrintUsage();
            return 2;
        }
        if (mode == "--help")
        {
            PrintUsage();
            return 0;
        }
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000) || !Environment.UserInteractive ||
            RuntimeInformation.ProcessArchitecture != RuntimeInformation.OSArchitecture ||
            RuntimeInformation.ProcessArchitecture is not (Architecture.X64 or Architecture.Arm64))
        {
            Console.Error.WriteLine("Requires an interactive Windows 11 desktop and native x64 or Arm64 .NET.");
            return 3;
        }
        try
        {
            using var lease = new Mutex(false, @"Local\Monochrome.WindowsProbe.v1");
            bool locked;
            try { locked = lease.WaitOne(0); }
            catch (AbandonedMutexException) { locked = true; }
            if (!locked) { Console.Error.WriteLine("Another probe is already running in this session."); return 4; }
            try { return Run(mode); }
            finally { lease.ReleaseMutex(); }
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"Windows API unavailable: {ex.GetType().Name}");
            return 4;
        }
    }

    private static int Run(string mode)
    {
        using var display = WindowsMagnifier.Open();
        if (display is null) { Console.Error.WriteLine("MagInitialize failed; no color write attempted."); return 4; }
        if (mode == "--restore-probe-matrix")
        {
            var recovery = Probe.RestoreKnownProbeMatrix(display);
            Console.WriteLine($"Recovery: {recovery}.");
            return recovery == FlashResult.Restored ? 0 : 4;
        }
        if (mode == "--check")
        {
            var check = Probe.Check(display);
            Console.WriteLine($"READ ONLY: {check}; no color write attempted.");
            return check switch { CheckResult.Identity => 0, CheckResult.NonIdentity => 5, _ => 4 };
        }

        Console.WriteLine("Testing a 1.5-second grayscale pulse. Keep this window open. Ctrl+C requests early cleanup.");
        Console.CancelKeyPress += Cancel;
        FlashResult result;
        try
        {
            result = Probe.Flash(display, () => {
                if (Stop.Wait(HoldMilliseconds)) throw new OperationCanceledException();
            });
        }
        finally { Console.CancelKeyPress -= Cancel; }
        Console.WriteLine(result switch {
            FlashResult.Restored => "PASS readback: grayscale confirmed, original matrix restored. Check the physical colors separately.",
            FlashResult.InterruptedRestored => "Interrupted: original matrix restored.",
            FlashResult.ApplyNotVerifiedRestored => "Grayscale not confirmed at start; original matrix restored during cleanup.",
            FlashResult.ExistingEffect => "Skipped: a non-identity matrix is already active. No color write attempted.",
            FlashResult.ChangedExternally => "Matrix changed during the test; the probe did not overwrite it.",
            FlashResult.RestoreNotVerified => "WARNING: restoration could not be verified. See the recovery note in README.ru.md.",
            _ => $"Probe did not pass: {result}."
        });
        return result switch { FlashResult.Restored => 0, FlashResult.InterruptedRestored => 130, FlashResult.ExistingEffect => 5, _ => 4 };
    }

    private static void Cancel(object? sender, ConsoleCancelEventArgs e) { e.Cancel = true; Stop.Set(); }
    private static void PrintUsage() => Console.WriteLine("Monochrome.WindowsProbe [--check | --flash | --restore-probe-matrix | --help]\nDefault: read only. --flash explicitly runs a 1.5-second screen test. See README.ru.md before recovery.");
}
