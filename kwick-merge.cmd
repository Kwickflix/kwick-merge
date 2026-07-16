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

REM The banner art needs 140+ columns, so open a window wide enough for it.
where wt.exe >nul 2>&1
if not errorlevel 1 (
  wt.exe --size 150,40 --pos 0,0 --title Kwick_Merge powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Folder "%~1"
  exit /b
)

REM No Windows Terminal - fall back to a plain console
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Folder "%~1"
pause
