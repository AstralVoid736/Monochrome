import contextlib
import io
import os
import signal
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

import probe


class FakeKWin:
    def __init__(self):
        self.supported = True
        self.active = False
        self.safe = True
        self.owner_matches = True
        self.result = True
        self.lose_reply = False
        self.ignore_load = False
        self.ignore_unload = False
        self.break_loaded = set()
        self.reads = 0
        self.calls = []

    def is_supported(self):
        return self.supported

    def is_loaded(self):
        self.reads += 1
        if self.reads in self.break_loaded:
            raise probe.ProbeError('fixture unreadable')
        return self.active

    def config_ready(self):
        return self.safe

    def same_owner(self):
        return self.owner_matches

    def load(self):
        self.calls.append('load')
        if self.result and not self.ignore_load:
            self.active = True
        if self.lose_reply:
            raise probe.ProbeError('fixture lost reply')
        return self.result

    def unload(self):
        self.calls.append('unload')
        if not self.ignore_unload:
            self.active = False


class PulseTests(unittest.TestCase):
    def setUp(self):
        self.kwin = FakeKWin()
        self.stop = threading.Event()

    def pulse(self, hold=lambda _: False):
        return probe.flash(self.kwin, self.stop, hold)

    def test_readonly_reports_ready_without_effect_writes(self):
        self.assertEqual(probe.preflight(self.kwin), probe.Result.READY)
        self.assertEqual(self.kwin.calls, [])

    def test_pulse_confirms_load_then_restores_and_checks(self):
        def hold(seconds):
            self.assertEqual(seconds, 1.5)
            self.assertTrue(self.kwin.active)
            self.assertEqual(self.kwin.calls, ['load'])
            return False
        self.assertEqual(self.pulse(hold), probe.Result.RESTORED)
        self.assertFalse(self.kwin.active)
        self.assertEqual(self.kwin.calls, ['load', 'unload'])
        self.assertGreaterEqual(self.kwin.reads, 4)

    def test_existing_effect_is_not_touched(self):
        self.kwin.active = True
        self.assertEqual(self.pulse(), probe.Result.ALREADY_LOADED)
        self.assertEqual(self.kwin.calls, [])

    def test_wrong_mode_or_persistent_enable_is_not_touched(self):
        self.kwin.safe = False
        self.assertEqual(self.pulse(), probe.Result.NOT_CONFIGURED)
        self.assertEqual(self.kwin.calls, [])

    def test_unsupported_effect_is_not_touched(self):
        self.kwin.supported = False
        self.assertEqual(self.pulse(), probe.Result.UNSUPPORTED)
        self.assertEqual(self.kwin.calls, [])

    def test_unreadable_baseline_prevents_mutation(self):
        self.kwin.break_loaded.add(1)
        self.assertEqual(self.pulse(), probe.Result.UNAVAILABLE)
        self.assertEqual(self.kwin.calls, [])

    def test_stop_before_load_prevents_mutation(self):
        self.stop.set()
        self.assertEqual(self.pulse(), probe.Result.CANCELLED)
        self.assertEqual(self.kwin.calls, [])

    def test_load_refusal_never_unloads(self):
        self.kwin.result = False
        self.assertEqual(self.pulse(), probe.Result.LOAD_REJECTED)
        self.assertEqual(self.kwin.calls, ['load'])

    def test_ambiguous_load_does_not_assume_ownership(self):
        self.kwin.lose_reply = True
        self.assertEqual(self.pulse(), probe.Result.LOAD_UNKNOWN)
        self.assertTrue(self.kwin.active)
        self.assertEqual(self.kwin.calls, ['load'])

    def test_acknowledged_load_without_effect_is_not_pass(self):
        self.kwin.ignore_load = True
        self.assertEqual(self.pulse(), probe.Result.NOT_CONFIRMED)
        self.assertEqual(self.kwin.calls, ['load'])

    def test_short_interrupt_still_restores(self):
        self.assertEqual(self.pulse(lambda _: True), probe.Result.INTERRUPTED_RESTORED)
        self.assertEqual(self.kwin.calls, ['load', 'unload'])

    def test_unreadable_after_ack_attempts_guarded_cleanup(self):
        self.kwin.break_loaded.add(2)
        self.assertEqual(self.pulse(), probe.Result.NOT_CONFIRMED_RESTORED)
        self.assertEqual(self.kwin.calls, ['load', 'unload'])

    def test_owner_or_config_change_prevents_unload(self):
        for attr in ('owner_matches', 'safe'):
            with self.subTest(attr=attr):
                self.kwin = FakeKWin()
                def hold(_):
                    setattr(self.kwin, attr, False)
                    return False
                self.assertEqual(self.pulse(hold), probe.Result.CLEANUP_UNVERIFIED)
                self.assertEqual(self.kwin.calls, ['load'])

    def test_effect_disappearing_during_hold_is_not_a_pass(self):
        def hold(_):
            self.kwin.active = False
            return False
        self.assertEqual(self.pulse(hold), probe.Result.CHANGED)
        self.assertEqual(self.kwin.calls, ['load'])

    def test_unload_noop_is_not_a_pass(self):
        self.kwin.ignore_unload = True
        self.assertEqual(self.pulse(), probe.Result.CLEANUP_UNVERIFIED)

    def test_bad_cleanup_read_does_not_write_blindly(self):
        self.kwin.break_loaded.add(3)
        self.assertEqual(self.pulse(), probe.Result.CLEANUP_UNVERIFIED)
        self.assertEqual(self.kwin.calls, ['load'])


class TransportTests(unittest.TestCase):
    def test_bus_target_is_bound_to_unique_owner_and_arguments_are_fixed(self):
        calls = []
        def command(args):
            calls.append(args)
            return {'GetNameOwner': 's ":1.42"', 'isEffectSupported': 'b true',
                    'isEffectLoaded': 'b false', 'loadEffect': 'b true', 'unloadEffect': ''}[args[-3]]
        kwin = probe.KWin('busctl', 'kreadconfig6', command)
        self.assertTrue(kwin.is_supported())
        self.assertFalse(kwin.is_loaded())
        self.assertTrue(kwin.load())
        kwin.unload()
        for args, method in zip(calls[1:], ('isEffectSupported', 'isEffectLoaded', 'loadEffect', 'unloadEffect')):
            self.assertEqual(args[-6:], [':1.42', '/Effects', 'org.kde.kwin.Effects', method, 's', 'colorblindnesscorrection'])
            self.assertIn('--user', args)
            self.assertIn('--auto-start=no', args)
            self.assertIn('--allow-interactive-authorization=no', args)

    def test_unexpected_boolean_fails_closed(self):
        kwin = probe.KWin('busctl', 'kreadconfig6', lambda a: 's ":1.42"' if 'GetNameOwner' in a else 'true')
        with self.assertRaises(probe.ProbeError):
            kwin.is_loaded()

    def test_readconfig_only_and_requires_mode_three_full_strength_disabled(self):
        settings = {'Mode': '3', 'Intensity': '1.0', 'colorblindnesscorrectionEnabled': 'false'}
        def command(args):
            if 'GetNameOwner' in args:
                return 's ":1.42"'
            self.assertEqual(args[0], 'kreadconfig6')
            self.assertEqual(args[1:3], ['--file', 'kwinrc'])
            return settings[args[args.index('--key') + 1]]
        kwin = probe.KWin('busctl', 'kreadconfig6', command)
        self.assertTrue(kwin.config_ready())
        for key, bad in (('Mode', '2'), ('Intensity', '0.5'), ('colorblindnesscorrectionEnabled', 'true')):
            with self.subTest(key=key):
                original = settings[key]
                settings[key] = bad
                self.assertFalse(kwin.config_ready())
                settings[key] = original

    def test_real_terminal_child_runner_does_not_use_a_shell(self):
        self.assertEqual(probe.command([sys.executable, '-c', 'import sys; print(sys.argv[1])', 'a; b']), 'a; b')
        with self.assertRaises(probe.ProbeError):
            probe.command([sys.executable, '-c', 'raise SystemExit(7)'])

    def test_runtime_lock_excludes_same_session_and_releases(self):
        with tempfile.TemporaryDirectory() as directory:
            with probe.session_lock(directory):
                with self.assertRaises(probe.ProbeError):
                    with probe.session_lock(directory):
                        self.fail('second copy should not enter')
            with probe.session_lock(directory):
                pass
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_non_linux_do_not_attempt_tools(self):
        with patch.object(sys, 'platform', 'darwin'), patch.object(probe.shutil, 'which', side_effect=AssertionError('tool lookup')):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(probe.main([]), 3)
                self.assertEqual(probe.main(['--flash']), 3)

    def test_cli_direct_flash_without_terminal_confirmation_never_writes(self):
        with patch.object(probe, 'platform_ready', return_value=True), patch.object(probe, 'open_kwin', side_effect=AssertionError('tool lookup')), patch.object(sys.stdin, 'isatty', return_value=False):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(probe.main(['--flash']), 2)

    def test_signal_listener_restores_effect_and_then_restores_previous_handler(self):
        kwin = FakeKWin()
        stop = probe.StopRequest()
        initial = signal.getsignal(signal.SIGINT)
        with probe.catch_stop(stop):
            def hold(seconds):
                trigger = threading.Timer(0.05, os.kill, args=(os.getpid(), signal.SIGINT))
                trigger.start()
                try:
                    return stop.wait(seconds)
                finally:
                    trigger.join(1)
            self.assertEqual(probe.flash(kwin, stop, hold), probe.Result.INTERRUPTED_RESTORED)
        self.assertFalse(kwin.active)
        self.assertIs(signal.getsignal(signal.SIGINT), initial)


if __name__ == '__main__':
    unittest.main()
