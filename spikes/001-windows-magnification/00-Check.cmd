@echo off
setlocal
dotnet "%~dp0Monochrome.WindowsProbe.dll" --check
set "PROBE_EXIT=%ERRORLEVEL%"
pause
exit /b %PROBE_EXIT%
