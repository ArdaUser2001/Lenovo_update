# Worker entry point for non-GUI update tasks.
# Update-Assistent.ps1 launches this module in a hidden child PowerShell process so
# long-running work cannot freeze the WPF window.
Import-Module (Join-Path $PSScriptRoot 'LenovoTools.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'WindowsUpdate.psm1') -Force -ErrorAction Stop

function Invoke-Worker {
    param([string]$Mode,[string]$RunDirectory)

    # Each worker writes a plain text log for humans and result.json for the GUI.
    if ([string]::IsNullOrWhiteSpace($RunDirectory) -or -not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        throw 'Der Protokollordner fehlt.'
    }
    $log = Join-Path $RunDirectory 'details.txt'
    $resultPath = Join-Path $RunDirectory 'result.json'
    $result = [ordered]@{ Task=$Mode; Outcome='Attention'; Message='Bitte Ergebnis prüfen.'; ExitCode=$null; Time=(Get-Date).ToString('o') }
    try {
        "Start: $Mode | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -LiteralPath $log -Encoding UTF8

        # Lenovo tasks install the helper tool only; users still run the device check manually.
        if ($Mode -in @('LenovoVantage','LenovoSystemUpdate')) {
            $kind = if ($Mode -eq 'LenovoVantage') { 'Vantage' } else { 'SystemUpdate' }
            $result = Install-LenovoTool -Kind $kind -Log $log
        } elseif ($Mode -eq 'Windows') {
            $result = Invoke-WindowsCycle -Log $log
        } elseif ($Mode -eq 'Defender') {
            # Defender status is verified before and after the signature update.
            Import-Module Defender -ErrorAction Stop
            $before = Get-MpComputerStatus -ErrorAction Stop
            if (-not $before.AMServiceEnabled -or -not $before.AntivirusEnabled -or $before.AMRunningMode -ne 'Normal') {
                throw 'Microsoft Defender ist nicht als aktiver Virenschutz verfügbar. Bitte Windows-Sicherheit öffnen und den dort verwendeten Virenschutz prüfen.'
            }
            Update-MpSignature -ErrorAction Stop
            $after = Get-MpComputerStatus -ErrorAction Stop
            $after | Select-Object -Property @('AMRunningMode','AntivirusEnabled','RealTimeProtectionEnabled','AntivirusSignatureVersion','AntivirusSignatureLastUpdated','AntivirusSignatureAge') | Format-List | Out-String | Add-Content -LiteralPath $log -Encoding UTF8
            if ($after.RealTimeProtectionEnabled -and $after.AntivirusEnabled -and $after.AMRunningMode -eq 'Normal' -and $null -ne $after.AntivirusSignatureLastUpdated -and $after.AntivirusSignatureAge -le 1) {
                $result.Outcome = 'Done'
                $result.Message = 'Defender-Signaturen geprüft und aktualisiert; Echtzeitschutz ist aktiv. Prüfen Sie zusätzlich die Hinweise in Windows-Sicherheit.'
            } else {
                $result.Message = 'Die Aktualisierung wurde ausgeführt, aber der Schutzstatus braucht Aufmerksamkeit. Öffnen Sie Windows-Sicherheit.'
            }
        } else {
            # Scan and Install share winget; Install adds package installation flags.
            $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $winget) { throw 'App-Installer (winget) fehlt. Aktualisieren oder installieren Sie App-Installer im Microsoft Store. Nutzen Sie bis dahin die manuellen Update-Funktionen der Programme.' }
            $cliArguments = @('upgrade','--source','winget','--accept-source-agreements','--disable-interactivity')
            if ($Mode -eq 'Install') { $cliArguments += @('--all','--silent','--accept-package-agreements') }
            # Kein --allow-reboot, --force, --include-unknown oder --include-pinned.
            # Stderr von nativen Programmen darf unter Windows PowerShell 5.1 nicht
            # allein als terminierender PowerShell-Fehler behandelt werden.
            $ErrorActionPreference = 'Continue'
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding
            & $winget.Source @cliArguments 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $log -Encoding UTF8
            $nativeCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            $result.ExitCode = $nativeCode
            $unsignedCode = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$nativeCode),0)
            if ($unsignedCode -eq [Convert]::ToUInt32('8A15002B',16)) {
                $result.Outcome = 'Done'
                $result.Message = 'Für die von winget berücksichtigten Programme wurden keine passenden Updates gefunden. Store-Apps und andere Programme bitte separat prüfen.'
            } elseif ($nativeCode -eq 0) {
                if ($Mode -eq 'Scan') {
                    $result.Outcome = 'Scanned'
                    $result.Message = 'Suche abgeschlossen. Die gefundenen Programme stehen unter Details. Mit «Programme aktualisieren» starten Sie die Installation.'
                } else {
                    $result.Outcome = 'Done'
                    $result.Message = 'winget hat den Durchlauf ohne gemeldeten Fehler beendet. Prüfen Sie unter Details, ob Programme übersprungen wurden. Browser anschließend neu öffnen.'
                }
            } else {
                $hex = '0x{0:X8}' -f $unsignedCode
                $result.Message = "Der Durchlauf ist nicht vollständig bestätigt (Code $hex). Prüfen Sie die Details. Speichern und schließen Sie offene Programme; versuchen Sie es erneut oder nutzen Sie die manuelle Anleitung."
            }
        }
    } catch {
        # Convert all task failures into a readable GUI message and keep details in the log.
        $result.Outcome = 'Attention'
        $result.Message = $_.Exception.Message
        $_ | Out-String | Add-Content -LiteralPath $log -Encoding UTF8
    }

    # The GUI polls this file and maps Outcome to localized status text/icons.
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}


Export-ModuleMember -Function Invoke-Worker
