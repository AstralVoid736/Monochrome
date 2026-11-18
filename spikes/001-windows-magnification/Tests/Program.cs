using System;
using System.Collections.Generic;

static class Tests
{
    private static int count;
    private static readonly Effect Outside = With(Effect.Identity, 0, .7f);

    public static void Main()
    {
        Run("matrix ABI and grayscale colors", () => {
            Require(System.Runtime.InteropServices.Marshal.SizeOf<Effect>() == 100);
            foreach (var rgb in new[] { (1f, 0f, 0f), (0f, 1f, 0f), (0f, 0f, 1f), (1f, 1f, 1f) }) {
                var effect = Effect.Gray;
                var r = rgb.Item1 * effect[0] + rgb.Item2 * effect[5] + rgb.Item3 * effect[10];
                for (var i = 1; i < 3; ++i)
                    Require(r == rgb.Item1 * effect[i] + rgb.Item2 * effect[5 + i] + rgb.Item3 * effect[10 + i]);
                Require(r > 0 && r <= 1);
            }
            Require(Effect.Gray[18] == 1 && Effect.Gray[24] == 1);
            Require(Effect.Gray != Effect.Identity);
        });
        Run("read-only check, including existing effect", () => {
            var fake = new Fake { State = Outside };
            Require(Probe.Check(fake) == CheckResult.NonIdentity && fake.Reads == 1 && fake.Writes.Count == 0);
            fake.State = Effect.Identity;
            Require(Probe.Check(fake) == CheckResult.Identity && fake.Writes.Count == 0);
            fake.HideRead = _ => true;
            Require(Probe.Check(fake) == CheckResult.Unreadable && fake.Writes.Count == 0);
        });
        Run("confirmed apply, delay and exact restore", () => {
            var fake = new Fake();
            var during = false;
            Require(Probe.Flash(fake, () => { during = true; Require(fake.State == Effect.Gray && fake.Reads == 2); }) == FlashResult.Restored);
            Require(during && fake.State == Effect.Identity && fake.Writes.Count == 2 && fake.Writes[0] == Effect.Gray && fake.Writes[1] == Effect.Identity);
        });
        Run("prior external or identical gray transform is not ours", () => {
            foreach (var value in new[] { Outside, Effect.Gray }) {
                var fake = new Fake { State = value };
                Require(Probe.Flash(fake, NoDelay) == FlashResult.ExistingEffect && fake.Writes.Count == 0);
            }
        });
        Run("unreadable start prevents writes", () => {
            var fake = new Fake { HideRead = _ => true };
            Require(Probe.Flash(fake, NoDelay) == FlashResult.ReadFailed && fake.Writes.Count == 0);
        });
        Run("write failure is not a confirmed start", () => {
            var fake = new Fake { RejectSet = _ => true };
            Require(Probe.Flash(fake, NoDelay) == FlashResult.SetFailed && fake.Writes.Count == 1 && fake.State == Effect.Identity);
        });
        Run("successful but ignored write is not a confirmed start", () => {
            var fake = new Fake { IgnoreSet = _ => true };
            Require(Probe.Flash(fake, NoDelay) == FlashResult.NotConfirmed && fake.Writes.Count == 1);
        });
        Run("failed verification still attempts guarded cleanup", () => {
            var fake = new Fake { HideRead = n => n == 2 };
            Require(Probe.Flash(fake, NoDelay) == FlashResult.ApplyNotVerifiedRestored && fake.Writes.Count == 2 && fake.State == Effect.Identity);
        });
        Run("external change is never overwritten deliberately", () => {
            foreach (var value in new[] { Outside, Effect.Identity }) {
                var fake = new Fake();
                Require(Probe.Flash(fake, () => fake.State = value) == FlashResult.ChangedExternally);
                Require(fake.State == value && fake.Writes.Count == 1);
            }
        });
        Run("unreadable cleanup prevents blind writes", () => {
            var fake = new Fake { HideRead = n => n == 3 };
            Require(Probe.Flash(fake, () => {}) == FlashResult.RestoreNotVerified && fake.Writes.Count == 1);
        });
        Run("restore rejection, silent no-op and unreadable readback are failures", () => {
            foreach (var configure in new Action<Fake>[] { f => f.RejectSet = n => n == 2, f => f.IgnoreSet = n => n == 2, f => f.HideRead = n => n == 4 }) {
                var fake = new Fake();
                configure(fake);
                Require(Probe.Flash(fake, () => {}) == FlashResult.RestoreNotVerified && fake.Writes.Count == 2);
            }
        });
        Run("exception during delay still restores", () => {
            var fake = new Fake();
            Require(Probe.Flash(fake, () => throw new OperationCanceledException()) == FlashResult.InterruptedRestored);
            Require(fake.State == Effect.Identity && fake.Writes.Count == 2);
        });
        Run("explicit recovery refuses unmatched matrices and checks readback", () => {
            foreach (var value in new[] { Outside, Effect.Identity }) {
                var fake = new Fake { State = value };
                Require(Probe.RestoreKnownProbeMatrix(fake) == FlashResult.ChangedExternally && fake.Writes.Count == 0);
            }
            var own = new Fake { State = Effect.Gray };
            Require(Probe.RestoreKnownProbeMatrix(own) == FlashResult.Restored && own.State == Effect.Identity && own.Writes.Count == 1);
            var unknown = new Fake { State = Effect.Gray, HideRead = _ => true };
            Require(Probe.RestoreKnownProbeMatrix(unknown) == FlashResult.ReadFailed && unknown.Writes.Count == 0);
            var silent = new Fake { State = Effect.Gray, IgnoreSet = _ => true };
            Require(Probe.RestoreKnownProbeMatrix(silent) == FlashResult.RestoreNotVerified && silent.State == Effect.Gray);
        });
        Console.WriteLine($"PASS: {count} cases (pure model / synthetic display; not Windows runtime)");
    }

    private static void Run(string name, Action body)
    {
        try { body(); }
        catch (Exception ex) { throw new InvalidOperationException(name, ex); }
        ++count;
        Console.WriteLine($"PASS {name}");
    }
    private static void Require(bool value) { if (!value) throw new InvalidOperationException("assertion failed"); }
    private static void NoDelay() => throw new InvalidOperationException("hold must not run here");
    private static Effect With(Effect effect, int index, float value) { effect[index] = value; return effect; }

    private sealed class Fake : IDisplay
    {
        public Effect State = Effect.Identity;
        public int Reads;
        public readonly List<Effect> Writes = new();
        public Func<int, bool> HideRead = _ => false;
        public Func<int, bool> RejectSet = _ => false;
        public Func<int, bool> IgnoreSet = _ => false;
        public bool TryGet(out Effect effect) { effect = State; return !HideRead(++Reads); }
        public bool TrySet(Effect effect)
        {
            Writes.Add(effect);
            if (RejectSet(Writes.Count)) return false;
            if (!IgnoreSet(Writes.Count)) State = effect;
            return true;
        }
    }
}
