@echo off
rem Paths are passed through the environment, never interpolated into PowerShell code.
setlocal
set "WFW_PACKAGE_ROOT=%~dp0"
set "WFW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WFW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
title WFW Update-Assistent
cd /d "%~dp0"
echo WFW Update-Assistent wird vorbereitet ...
rem Inline preflight can inspect downloaded files before any unsigned script is loaded.
rem RemoteSigned applies only to these processes; enforced Group Policy still wins.
"%WFW_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -Command ^
  "$ErrorActionPreference = 'Stop'; try {" ^
  "$policy = Get-ExecutionPolicy; if ($policy -eq 'Restricted') { throw 'Die Firmenrichtlinie sperrt PowerShell-Skripte. Bitte IT Germany kontaktieren.' };" ^
  "$names = @('Programm\Update-Assistent.ps1','Programm\Module\Updates.psm1','Programm\Module\WindowsUpdate.psm1','Programm\Module\LenovoTools.psm1','IT\Validieren.ps1');" ^
  "$files = @($names | ForEach-Object { Get-Item -LiteralPath (Join-Path $env:WFW_PACKAGE_ROOT $_) -ErrorAction Stop });" ^
  "if ($policy -eq 'AllSigned') { foreach ($file in $files) { if ((Get-AuthenticodeSignature -LiteralPath $file.FullName).Status -ne 'Valid') { throw 'Die Firmenrichtlinie verlangt signierte Skripte. IT muss dieses Paket mit einem vertrauenswuerdigen Code-Signing-Zertifikat signieren.' } } };" ^
  "$blocked = @($files | Where-Object { Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue });" ^
  "if ($blocked.Count -gt 0 -and $policy -ne 'AllSigned') { Add-Type -AssemblyName PresentationFramework;" ^
  "$message = 'Dieses Paket wurde aus dem Internet geladen. Nur fortfahren, wenn Sie die Quelle und den Inhalt geprueft haben.' + [Environment]::NewLine + [Environment]::NewLine + 'Die Download-Markierung wird nur von den fuenf PowerShell-Dateien dieses Pakets entfernt. Die Windows-Richtlinie bleibt unveraendert.' + [Environment]::NewLine + [Environment]::NewLine + $env:WFW_PACKAGE_ROOT + [Environment]::NewLine + [Environment]::NewLine + 'Diesem Paket vertrauen und starten?';" ^
  "if ([Windows.MessageBox]::Show($message, 'WFW - Paket einmalig freigeben', 'YesNo', 'Question', 'No') -ne 'Yes') { exit 2 };" ^
  "$blocked | ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction Stop };" ^
  "foreach ($file in $blocked) { if (Get-Item -LiteralPath $file.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) { throw 'Die Download-Markierung konnte nicht entfernt werden. Paket in einen eigenen lokalen Ordner entpacken und erneut starten.' } } };" ^
  "exit 0 } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Get-ExecutionPolicy -List | Format-Table; exit 1 }"
if "%ERRORLEVEL%"=="2" exit /b 0
if errorlevel 1 goto failed
rem WPF needs STA. Worker processes and restart resume retain RemoteSigned too.
"%WFW_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0Programm\Update-Assistent.ps1"
if errorlevel 1 goto failed
exit /b 0
:failed
echo.
echo Der Assistent konnte nicht gestartet werden.
echo Bitte die obige Meldung an IT Germany weitergeben.
echo Bei AllSigned ist ein von IT signiertes Paket erforderlich.
echo Oeffnen Sie START-HIER.txt fuer weitere Hinweise.
pause
exit /b 1
