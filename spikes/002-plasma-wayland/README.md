# Monochrome — KDE Plasma 6.6 / Wayland diagnostic

**0.1.0-alpha.1 · Test release, not the full app.** This terminal tool briefly loads KWin's built-in color correction effect and checks that it unloads afterwards. KWin applies the effect to compositor windows; a D-Bus success does not mean the entire physical output was grayscale. There is no tray icon, global shortcut or 25-minute timer yet.

1. Extract the whole archive. Use an ordinary **KDE Plasma 6.6.x Wayland session** with Python 3.9+, `busctl`, `kreadconfig6` and `plasmashell` already available. Run as the logged-in desktop user, without `sudo`. Other desktops, Plasma versions and X11 are outside this release's scope.
2. If you rely on existing color correction, use a separate test session. In **System Settings → Accessibility → Color Blindness Correction**, enable the effect, select **Monochrome**, set maximum intensity and apply. Check that it looks gray. Then **disable the effect and apply again**, leaving Monochrome and its intensity selected. The desktop should be back in color. Close System Settings and do not change effects during the pulse. If there is no Monochrome option, stop.
3. In a terminal opened in the extracted folder, run `python3 probe.py --check`. Continue only if it reports `READ ONLY: READY`. This checks the stored selection and KWin effect state, without loading or unloading anything.
4. Run `python3 probe.py --flash` and type `y` when prompted. Keep the terminal open and look at a colorful window, wallpaper and panel. Note whether they went gray for about 1.5 seconds and whether color returned. Check fullscreen content, the cursor, HDR and other monitors separately. `PASS readback` only reports KWin's load and unload state.

The script does not write `kwinrc`, install plugins or use the network. Step 2 is a manual preference change; restore your original selection if you changed it. `Ctrl+C` requests early cleanup. If the screen stays gray or the script warns about cleanup, **do not rerun**. If the effect was disabled in System Settings before the pulse, save your work, sign out and sign in again to reload the persistent setting. A timeout or a killed process can leave the effect loaded until the session ends. Do not toggle other effects in parallel with the test.

Report the Plasma and KWin versions, monitor count, HDR status, the visible result and the short console result. Avoid posting personal data. The automated checks ran on macOS against a simulated KWin backend; they do not confirm physical Plasma output.

- [Russian instructions](README.ru.md)
- Source-tree tests: `python3 -B -m unittest -v test_probe` in `spikes/002-plasma-wayland`.
- Upstream: [KWin effect](https://github.com/KDE/kwin/blob/v6.6.0/src/plugins/colorblindnesscorrection/colorblindnesscorrection.cpp) and [D-Bus interface](https://github.com/KDE/kwin/blob/v6.6.0/src/org.kde.kwin.Effects.xml).
