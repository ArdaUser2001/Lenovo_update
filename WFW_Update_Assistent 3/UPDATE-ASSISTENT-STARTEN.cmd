@echo off
setlocal
title WFW Update-Assistent
cd /d "%~dp0"
echo WFW Update-Assistent wird geoeffnet.
echo Bitte dieses Startfenster waehrend der Nutzung geoeffnet lassen.
echo.
set "WFW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WFW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%WFW_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0Programm\Update-Assistent.ps1"
if errorlevel 1 (
  echo.
  echo Der Assistent konnte nicht gestartet werden.
  echo Oeffnen Sie START-HIER.txt oder nutzen Sie die manuelle PDF-Anleitung.
  echo Eine Unternehmensrichtlinie darf nicht umgangen werden.
  pause
)
endlocal
