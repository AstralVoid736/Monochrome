@echo off
setlocal
echo This test briefly changes the colors of the Windows desktop.
echo Keep this window open until the test reports its result.
choice /C YN /N /M "Run the 1.5-second grayscale test? [Y/N] "
if not "%ERRORLEVEL%"=="1" exit /b 0
dotnet "%~dp0Monochrome.WindowsProbe.dll" --flash
set "PROBE_EXIT=%ERRORLEVEL%"
pause
exit /b %PROBE_EXIT%
