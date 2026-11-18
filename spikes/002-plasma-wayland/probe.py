#!/usr/bin/env python3
"""One-shot diagnostic for the built-in KWin monochrome effect."""
import argparse
import contextlib
from enum import Enum
import fcntl
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import time

VERSION = '0.1.0-alpha.1'
EFFECT = 'colorblindnesscorrection'
SERVICE = 'org.kde.KWin'
INTERFACE = 'org.kde.kwin.Effects'
SLOT = 'Effect-colorblindnesscorrection'


class Result(Enum):
    READY = 'READ ONLY: READY. Configured for full monochrome; KWin effect not loaded.'
    RESTORED = 'PASS readback: effect loaded, then unloaded. Check visible colors separately.'
    INTERRUPTED_RESTORED = 'Interrupted: KWin confirmed the effect is unloaded.'
    NOT_CONFIRMED_RESTORED = 'Effect load was not confirmed by readback; KWin confirmed the effect is unloaded.'
    NOT_CONFIRMED = 'KWin reported success but the effect was not loaded when checked.'
    CANCELLED = 'Cancelled before changing the effect.'
    LOAD_REJECTED = 'KWin refused to load the effect. No unload attempted.'
    LOAD_UNKNOWN = 'WARNING: load reply missing or invalid. No unload attempted without confirmed ownership. See recovery in README.'
    CHANGED = 'The effect was already unloaded before cleanup. Visual result not confirmed.'
    CLEANUP_UNVERIFIED = 'WARNING: cannot safely verify or restore the effect. See recovery in README.'
    ALREADY_LOADED = 'STOP: KWin already has color correction loaded; no effect write attempted.'
    NOT_CONFIGURED = 'STOP: select full-strength Monochrome and leave the effect disabled in System Settings. See README.'
    UNSUPPORTED = 'STOP: this KWin session does not support the effect.'
    UNAVAILABLE = 'STOP: cannot read the baseline, KWin effect state, or safe configuration.'


class ProbeError(Exception):
    pass


class StopRequest:
    # Only accessed on the main thread. The signal handler must not take locks.
    requested = False

    def is_set(self):
        return self.requested

    def wait(self, seconds):
        deadline = time.monotonic() + seconds
        while not self.requested:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            time.sleep(min(0.05, remaining))
        return True


def preflight(kwin):
    try:
        if not kwin.is_supported():
            return Result.UNSUPPORTED
        if not kwin.config_ready():
            return Result.NOT_CONFIGURED
        if not kwin.same_owner():
            return Result.UNAVAILABLE
        if kwin.is_loaded():
            return Result.ALREADY_LOADED
    except ProbeError:
        return Result.UNAVAILABLE
    return Result.READY


def cleanup(kwin, result):
    try:
        if not kwin.same_owner() or not kwin.config_ready():
            return Result.CLEANUP_UNVERIFIED
        if not kwin.is_loaded():
            return Result.CHANGED
        kwin.unload()
        if kwin.is_loaded() or not kwin.same_owner():
            return Result.CLEANUP_UNVERIFIED
        return result
    except ProbeError:
        return Result.CLEANUP_UNVERIFIED


def flash(kwin, stop, hold):
    status = preflight(kwin)
    if status != Result.READY:
        return status
    if stop.is_set():
        return Result.CANCELLED
    try:
        accepted = kwin.load()
    except ProbeError:
        return Result.LOAD_UNKNOWN
    if not accepted:
        return Result.LOAD_REJECTED
    result = Result.NOT_CONFIRMED_RESTORED
    try:
        try:
            loaded = kwin.is_loaded()
        except ProbeError:
            loaded = None
        if loaded is False:
            result = Result.NOT_CONFIRMED
        elif loaded is True:
            result = Result.INTERRUPTED_RESTORED if hold(1.5) else Result.RESTORED
    finally:
        if result != Result.NOT_CONFIRMED:
            result = cleanup(kwin, result)
    return result


def command(args):
    try:
        completed = subprocess.run(args, check=False, capture_output=True, text=True,
                                   encoding='utf-8', errors='strict', timeout=3, start_new_session=True,
                                   env=dict(os.environ, LC_ALL='C'))
    except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
        raise ProbeError('system command unavailable or timed out') from exc
    if completed.returncode != 0 or len(completed.stdout) > 4096:
        raise ProbeError('system command failed or gave an unexpected reply')
    return completed.stdout.strip()


class KWin:
    def __init__(self, busctl, reader, run=command):
        self.args = [busctl, '--user', '--auto-start=no', '--allow-interactive-authorization=no', '--timeout=2s', 'call']
        self.reader = reader
        self.run = run
        self.owner = self.current_owner()

    def current_owner(self):
        dbus = 'org.freedesktop.DBus'
        response = self.run(self.args + [dbus, '/org/freedesktop/DBus', dbus, 'GetNameOwner', 's', SERVICE])
        match = re.fullmatch(r's "(:1\.[0-9]+)"', response)
        if not match:
            raise ProbeError('invalid KWin owner reply')
        return match[1]

    def same_owner(self):
        return self.current_owner() == self.owner

    def config_ready(self):
        def read(group, key, default):
            return self.run([self.reader, '--file', 'kwinrc', '--group', group, '--key', key, '--default', default])
        return (read(SLOT, 'Mode', '0') == '3'
                and re.fullmatch(r'1(?:\.0+)?', read(SLOT, 'Intensity', '1.0')) is not None
                and read('Plugins', EFFECT + 'Enabled', 'false').lower() in ('false', '0'))

    def call(self, method):
        return self.run(self.args + [self.owner, '/Effects', INTERFACE, method, 's', EFFECT])

    def boolean(self, method):
        value = self.call(method)
        if value not in ('b true', 'b false'):
            raise ProbeError('unexpected boolean reply from KWin')
        return value == 'b true'

    def is_supported(self):
        return self.boolean('isEffectSupported')

    def is_loaded(self):
        return self.boolean('isEffectLoaded')

    def load(self):
        return self.boolean('loadEffect')

    def unload(self):
        if self.call('unloadEffect') != '':
            raise ProbeError('unexpected unload reply from KWin')


@contextlib.contextmanager
def session_lock(directory):
    fd = None
    try:
        info = os.lstat(directory)
        if (not os.path.isabs(directory) or not stat.S_ISDIR(info.st_mode)
                or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700):
            raise ProbeError('XDG_RUNTIME_DIR must be the private directory for this user')
        path = os.path.join(directory, 'monochrome-plasma-probe.lock')
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
            raise ProbeError('invalid probe lock')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, ProbeError) as exc:
        if fd is not None:
            os.close(fd)
        raise ProbeError('cannot acquire private session lock; another probe may be running') from exc
    try:
        yield
    finally:
        os.close(fd)


def platform_ready():
    return (sys.platform.startswith('linux') and os.geteuid() != 0
            and os.environ.get('XDG_SESSION_TYPE') == 'wayland'
            and 'KDE' in os.environ.get('XDG_CURRENT_DESKTOP', '').split(':')
            and os.environ.get('KDE_SESSION_VERSION') == '6'
            and bool(os.environ.get('WAYLAND_DISPLAY')))


def open_kwin():
    busctl, reader, shell = (shutil.which(exe) for exe in ('busctl', 'kreadconfig6', 'plasmashell'))
    if not (busctl and reader and shell):
        raise ProbeError('busctl, kreadconfig6 and plasmashell must already be installed')
    if not re.fullmatch(r'plasmashell 6\.6\.[0-9]+', command([shell, '--version'])):
        raise ProbeError('this probe only targets KDE Plasma 6.6.x')
    return KWin(busctl, reader)


def confirmed():
    if sys.stdin.isatty():
        try:
            return input('Run a 1.5-second grayscale test? Keep this terminal open. [y/N] ').strip().lower() == 'y'
        except (EOFError, KeyboardInterrupt):
            pass
    return False


@contextlib.contextmanager
def catch_stop(stop):
    def stop_soon(_sig, _frame):
        stop.requested = True
    signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    previous = {sig: signal.signal(sig, stop_soon) for sig in signals}
    try:
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main(args=None):
    parser = argparse.ArgumentParser(description='Monochrome diagnostic: KDE Plasma 6.6.x / Wayland. Default: read only.')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='read readiness; do not change the effect')
    mode.add_argument('--flash', action='store_true', help='offer a 1.5-second optical test in an interactive terminal')
    parser.add_argument('--version', action='version', version=VERSION)
    opts = parser.parse_args(args)
    if not platform_ready():
        print('Requires a normal Linux KDE Plasma 6 Wayland desktop session (no sudo).', file=sys.stderr)
        return 3
    if opts.flash and not confirmed():
        print('No confirmation; no effect was changed.', file=sys.stderr)
        return 2
    try:
        if opts.flash:
            stop = StopRequest()
            with catch_stop(stop), session_lock(os.environ.get('XDG_RUNTIME_DIR', '')):
                status = flash(open_kwin(), stop, stop.wait)
        else:
            status = preflight(open_kwin())
    except ProbeError as exc:
        print(f'STOP: {exc}', file=sys.stderr)
        return 4
    print(status.value)
    if status in (Result.READY, Result.RESTORED):
        return 0
    return 130 if status == Result.INTERRUPTED_RESTORED else 4


if __name__ == '__main__':
    sys.exit(main())
