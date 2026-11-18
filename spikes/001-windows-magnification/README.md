# Windows 11 — full-screen grayscale feasibility probe

**Verdict: PARTIAL.** The dependency-free .NET project builds against the installed .NET 8 SDK. The probe and its simulated-backend tests run on macOS; an interactive Windows 11 session is still required to establish whether the Magnification API affects the physical output on the intended host. This is not the port or an installer.

1. Extract the entire ZIP. Launch in a normal interactive Windows 11 session, not as an administrator. You need an existing native x64 or Arm64 **.NET 8 Runtime** (`dotnet --list-runtimes` should report `Microsoft.NETCore.App 8.0.x`).
2. Run `00-Check.cmd`. Continue only if it reports `READ ONLY: Identity`; this command does not write a matrix.
3. Run `01-Test.cmd`, then confirm with `Y`. Keep the window open, look at a colored desktop object, and record whether it became grayscale for 1.5 seconds and returned to color. Save the console result as a separate observation. `PASS readback` describes the API matrix, not what the monitor showed.

The probe refuses an existing non-identity matrix and verifies the restoration. It never writes registry keys, installs dependencies, or injects keys. Do not change Magnifier or another color effect during the test: Win32 get/set are separate calls, not an atomic compare-and-set. Ctrl+C requests early cleanup. Closing the terminal or killing the process can prevent cleanup.

Only if the screen stayed gray immediately after this probe, use `dotnet .\Monochrome.WindowsProbe.dll --restore-probe-matrix` from the extracted folder. It attempts restoration only if the matrix is exactly the one this probe applies and verifies the result. An exact match alone does not prove ownership, so do not use this command on another app's filter. If recovery is not confirmed, keep the console result and sign out and back in if needed before trying any further test.

See [Microsoft Magnification API](https://learn.microsoft.com/en-us/windows/win32/winauto/magapi/magapi-intro) and the [Russian instructions](README.ru.md). There is no tray item, global shortcut, or 25-minute mode in this probe. Windows execution, HDR, multiple monitors, fullscreen apps, lock and sleep are unverified. The release DLL is not Authenticode-signed. Verify the ZIP with `SHA256SUMS.txt` from the same release; do not disable Windows security.

## Build from this directory

With the .NET 8 SDK already installed, run `dotnet build Probe.csproj -c Release` and `dotnet run --project Tests/Tests.csproj -c Release`. Neither project has an external package dependency. The tests use a synthetic display backend; only the interactive diagnostic exercises the Windows display API.
