@echo off
REM Kwick_Merge launcher - drag a folder of audio files onto this file.
REM Looks for kwick-merge.ps1 sitting next to it, so the whole folder can live anywhere.

set "PS1=%~dp0kwick-merge.ps1"

if not exist "%PS1%" (
  echo Could not find kwick-merge.ps1 next to this launcher.
  echo Keep kwick-merge.cmd and kwick-merge.ps1 in the same folder.
  pause
  exit /b 1
)

if "%~1"=="" (
  echo Drag a folder onto this file.
  pause
  exit /b
)

REM No Windows Terminal at all - fall back to a plain console.
where wt.exe >nul 2>&1
if errorlevel 1 (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Folder "%~1"
  pause
  exit /b
)

REM If a Terminal window is already open, drop into it as a new TAB instead of
REM spawning another window. Otherwise open a fresh window sized for the banner.
tasklist /fi "imagename eq WindowsTerminal.exe" 2>nul | find /i "WindowsTerminal.exe" >nul
if errorlevel 1 (
  REM Nothing open - new window, 150 cols wide so the full banner fits.
  wt.exe --size 150,40 --pos 0,0 --title Kwick_Merge powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Folder "%~1"
) else (
  REM Terminal already open - new tab in the current window (inherits its size).
  wt.exe -w 0 new-tab --title Kwick_Merge powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Folder "%~1"
)
exit /b
