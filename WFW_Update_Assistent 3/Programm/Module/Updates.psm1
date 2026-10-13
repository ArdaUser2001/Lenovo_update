# Background worker dispatcher. Result files form the contract with the GUI poller.

Import-Module (Join-Path $PSScriptRoot 'LenovoTools.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'WindowsUpdate.psm1') -Force -ErrorAction Stop
# Run one update task and publish details.txt plus result.json for the GUI poller.
function Invoke-Worker {
    param([string]$Mode,[string]$RunDirectory,[switch]$IncludeOptionalDrivers)
    if ([string]::IsNullOrWhiteSpace($RunDirectory) -or -not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        throw 'Der Protokollordner fehlt.'
    }
    # Allows the GUI to reattach if it is interrupted while a worker is still running.
    $self = Get-Process -Id $PID -ErrorAction Stop
    @{Id=$PID;Started=$self.StartTime.ToUniversalTime().ToString('o')} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'worker.json') -Encoding UTF8
    $log = Join-Path $RunDirectory 'details.txt'
    $resultPath = Join-Path $RunDirectory 'result.json'
    $result = [ordered]@{
        Task = $Mode;
        Outcome = 'Attention';
        Message = 'Bitte Ergebnis prüfen.';
        ExitCode = $null;
        Time = (Get-Date).ToString('o')
    }
    try {
        "Start: $Mode | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -LiteralPath $log -Encoding UTF8
        if ($Mode -in @('LenovoVantage','LenovoSystemUpdate')) {
            $kind = if ($Mode -eq 'LenovoVantage') {
                'Vantage'
            } else {
                'SystemUpdate'
            }
            $result = Install-LenovoTool -Kind $kind -Log $log
        } elseif ($Mode -eq 'Windows') {
            $result = Invoke-WindowsCycle -Log $log
        } elseif ($Mode -eq 'Drivers') {
            $result = Invoke-DriverCycle -Log $log -IncludeOptional ([bool]$IncludeOptionalDrivers)
        } elseif ($Mode -eq 'DefenderSecure') {
            $result = Invoke-DefenderProtection -Log $log
        } elseif ($Mode -eq 'Defender') {
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
        } elseif ($Mode -in @('Scan','Install')) {
            $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $winget) {
                throw 'App-Installer (winget) fehlt. Aktualisieren oder installieren Sie App-Installer im Microsoft Store. Nutzen Sie bis dahin die manuellen Update-Funktionen der Programme.'
            }
            $cliArguments = @('upgrade','--source','winget','--accept-source-agreements','--disable-interactivity')
            if ($Mode -eq 'Install') {
                $cliArguments += @('--all','--silent','--accept-package-agreements')
            }
            # Kein --allow-reboot, --force, --include-unknown oder --include-pinned.
            # Stderr von nativen Programmen darf unter Windows PowerShell 5.1 nicht
            # allein als terminierender PowerShell-Fehler behandelt werden.
            $ErrorActionPreference = 'Continue'
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding
            & $winget.Source @cliArguments 2>&1 | ForEach-Object {
                "$_"
            } | Add-Content -LiteralPath $log -Encoding UTF8
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
        } else {
            throw 'Unbekannter Update-Auftrag.'
        }
    } catch {
        $result.Outcome = 'Attention'
        $result.Message = $_.Exception.Message
        $_ | Out-String | Add-Content -LiteralPath $log -Encoding UTF8
    }
    $result.Task = $Mode
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

# Enable supported Defender protections only when local settings may be changed.
function Invoke-DefenderProtection {
    param([string]$Log)
    Import-Module Defender -ErrorAction Stop
    $r = [ordered]@{Task='DefenderSecure';Outcome='Attention';Message='';ExitCode=$null;Time=(Get-Date).ToString('o');RebootRequired=$false}
    $before = Get-MpComputerStatus -ErrorAction Stop
    if (-not $before.AMServiceEnabled -or -not $before.AntivirusEnabled -or $before.AMRunningMode -ne 'Normal') {
        $r.Message='Microsoft Defender ist nicht der aktive Virenschutz. Bitte das vorhandene Virenschutzprogramm bzw. Windows-Sicherheit prüfen.'
        return $r
    }
    Update-MpSignature -ErrorAction Stop
    $preferences = Get-MpPreference -ErrorAction Stop
    $changes = @{}
    foreach ($name in @('DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableIOAVProtection','DisableOnAccessProtection')) {
        if ($preferences.$name -eq $true) { $changes[$name] = $false }
    }
    if ($changes.Count -gt 0) {
        try {
            Assert-UnmanagedDevice
            if ($before.IsTamperProtected -or (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender')) {
                throw 'Die Schutz-Einstellungen werden durch Manipulationsschutz oder Richtlinien verwaltet.'
            }
            $preferences | Select-Object DisableRealtimeMonitoring,DisableBehaviorMonitoring,DisableIOAVProtection,DisableOnAccessProtection |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path $Log) 'Defender-vorher.json') -Encoding UTF8
            Set-MpPreference @changes -ErrorAction Stop
        } catch {
            $_.Exception.Message | Add-Content -LiteralPath $Log -Encoding UTF8
        }
    }
    $after = Get-MpComputerStatus -ErrorAction Stop
    $after | Select-Object AMRunningMode,AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,OnAccessProtectionEnabled,AntivirusSignatureAge |
        Format-List | Out-String | Add-Content -LiteralPath $Log -Encoding UTF8
    if ($after.AMRunningMode -eq 'Normal' -and $after.AntivirusEnabled -and $after.RealTimeProtectionEnabled -and
        $after.BehaviorMonitorEnabled -and $after.IoavProtectionEnabled -and $after.OnAccessProtectionEnabled -and
        $null -ne $after.AntivirusSignatureLastUpdated -and $after.AntivirusSignatureAge -le 1) {
        $r.Outcome='Done'; $r.Message='Defender aktualisiert. Echtzeit-, Verhaltens-, Download- und Dateischutz sind aktiv.'
    } else {
        $r.Message='Defender wurde aktualisiert, aber nicht alle Schutzfunktionen konnten bestätigt werden. Bitte Windows-Sicherheit öffnen; IT kann verwaltete Einstellungen prüfen.'
    }
    $r
}
Export-ModuleMember -Function Invoke-Worker,Invoke-DefenderProtection
