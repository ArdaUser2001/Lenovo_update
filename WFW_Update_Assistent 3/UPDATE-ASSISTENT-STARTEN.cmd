@echo off
rem Start the Windows UI from this package, regardless of the current folder.
setlocal
title WFW Update-Assistent
cd /d "%~dp0"
echo WFW Update-Assistent wird geoeffnet.
echo Bitte dieses Startfenster waehrend der Nutzung geoeffnet lassen.
echo.
rem Prefer native 64-bit Windows PowerShell when launched from a 32-bit process.
set "WFW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WFW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
rem WPF needs STA; keep the existing RemoteSigned execution policy.
"%WFW_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0Programm\Update-Assistent.ps1"
rem Keep startup failures visible so the user can consult the manual.
if errorlevel 1 (
  echo.
  echo Der Assistent konnte nicht gestartet werden.
  echo Oeffnen Sie START-HIER.txt oder nutzen Sie die manuelle PDF-Anleitung.
  echo Eine Unternehmensrichtlinie darf nicht umgangen werden.
  pause
)
endlocal
