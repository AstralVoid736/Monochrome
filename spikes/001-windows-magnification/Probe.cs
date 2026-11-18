using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct Effect : IEquatable<Effect>
{
    private fixed float cells[25];

    public float this[int index]
    {
        get { if ((uint)index >= 25) throw new ArgumentOutOfRangeException(nameof(index)); return cells[index]; }
        set { if ((uint)index >= 25) throw new ArgumentOutOfRangeException(nameof(index)); cells[index] = value; }
    }

    public static Effect Identity
    {
        get
        {
            var value = default(Effect);
            for (int i = 0; i < 25; i += 6) value.cells[i] = 1;
            return value;
        }
    }

    public static Effect Gray
    {
        get
        {
            var value = default(Effect);
            for (int output = 0; output < 3; output++)
            {
                value.cells[output] = 0.2126f;
                value.cells[5 + output] = 0.7152f;
                value.cells[10 + output] = 0.0722f;
            }
            value.cells[18] = value.cells[24] = 1;
            return value;
        }
    }

    public bool Equals(Effect other)
    {
        for (int i = 0; i < 25; i++) if (!cells[i].Equals(other.cells[i])) return false;
        return true;
    }
    public override bool Equals(object? obj) => obj is Effect other && Equals(other);
    public override int GetHashCode()
    {
        var hash = new HashCode();
        for (int i = 0; i < 25; i++) hash.Add(cells[i]);
        return hash.ToHashCode();
    }
    public static bool operator ==(Effect left, Effect right) => left.Equals(right);
    public static bool operator !=(Effect left, Effect right) => !left.Equals(right);
}

internal interface IDisplay
{
    bool TryGet(out Effect effect);
    bool TrySet(Effect effect);
}

internal enum CheckResult { Identity, NonIdentity, Unreadable }
internal enum FlashResult
{
    Restored, InterruptedRestored, ApplyNotVerifiedRestored, ExistingEffect,
    ReadFailed, SetFailed, NotConfirmed, ChangedExternally, RestoreNotVerified
}

internal static class Probe
{
    public static CheckResult Check(IDisplay display) => !display.TryGet(out var current)
        ? CheckResult.Unreadable
        : current == Effect.Identity ? CheckResult.Identity : CheckResult.NonIdentity;

    public static FlashResult RestoreKnownProbeMatrix(IDisplay display)
    {
        if (!display.TryGet(out var current)) return FlashResult.ReadFailed;
        if (current != Effect.Gray) return FlashResult.ChangedExternally;
        return Restore(display, Effect.Identity) ? FlashResult.Restored : FlashResult.RestoreNotVerified;
    }

    private static bool Restore(IDisplay display, Effect original) =>
        display.TrySet(original) && display.TryGet(out var verified) && verified == original;

    public static FlashResult Flash(IDisplay display, Action delay)
    {
        if (!display.TryGet(out var original)) return FlashResult.ReadFailed;
        if (original != Effect.Identity) return FlashResult.ExistingEffect;
        if (!display.TrySet(Effect.Gray)) return FlashResult.SetFailed;

        FlashResult result = FlashResult.ApplyNotVerifiedRestored;
        try
        {
            if (display.TryGet(out var applied))
            {
                if (applied != Effect.Gray) result = FlashResult.NotConfirmed;
                else
                {
                    try { delay(); result = FlashResult.Restored; }
                    catch (OperationCanceledException) { result = FlashResult.InterruptedRestored; }
                }
            }
        }
        finally
        {
            if (result != FlashResult.NotConfirmed)
            {
                if (!display.TryGet(out var current)) result = FlashResult.RestoreNotVerified;
                else if (current != Effect.Gray) result = FlashResult.ChangedExternally;
                else if (!Restore(display, original)) result = FlashResult.RestoreNotVerified;
            }
        }
        return result;
    }
}
