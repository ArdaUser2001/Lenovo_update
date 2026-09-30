# Windows Update Agent; Windows 11 Pro. Keine Drittmodule erforderlich.
$ErrorActionPreference = 'Stop'
function Write-WuLog([string]$Log,[string]$Text) {
    ('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Text) | Add-Content -LiteralPath $Log -Encoding UTF8
}
function Assert-UnmanagedDevice {
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($computer.PartOfDomain) { throw 'Dieses Gerät gehört zu einer Domäne. Bitte den vorgesehenen Firmen-Updateweg verwenden.' }
    $join = & (Join-Path $env:SystemRoot 'System32\dsregcmd.exe') /status 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $join -notmatch 'AzureAdJoined\s*:\s*(YES|NO)') { throw 'Der Verwaltungsstatus konnte nicht sicher bestimmt werden. Bitte Windows Update manuell verwenden.' }
    if ($join -match 'AzureAdJoined\s*:\s*YES') { throw 'Dieses Gerät ist mit Microsoft Entra verbunden. Bitte den vorgesehenen Firmen-Updateweg verwenden.' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Enrollments') {
        foreach ($key in Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop) {
            $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ($entry.ProviderID -eq 'MS DM Server' -or $entry.DiscoveryServiceFullURL) { throw 'Eine Geräteverwaltung wurde erkannt. Die Update-Vorgaben werden nicht verändert.' }
        }
    }
    $policyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (Test-Path $policyRoot) {
        $p = Get-ItemProperty $policyRoot
        if ($p.WUServer -or $p.DisableWindowsUpdateAccess -eq 1 -or $p.SetDisableUXWUAccess -eq 1 -or $p.DoNotConnectToWindowsUpdateInternetLocations -eq 1) {
            throw 'Eine vorgegebene Updatequelle oder Updatebeschränkung wurde erkannt. Bitte Windows Update manuell verwenden.'
        }
        if (Test-Path (Join-Path $env:SystemRoot 'System32\GroupPolicy\Machine\Registry.pol')) {
            throw 'Lokale Gruppenrichtlinien und Updatevorgaben sind vorhanden. Der Assistent verändert diese Vorgaben nicht.'
        }
    }
}
function Ensure-AutomaticWindowsUpdates([string]$Log) {
    Assert-UnmanagedDevice
    $settings = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    if (Test-Path $settings) {
        $ux = Get-ItemProperty $settings
        foreach ($name in @('PauseUpdatesExpiryTime','PauseQualityUpdatesEndTime','PauseFeatureUpdatesEndTime')) {
            $value = $ux.$name
            if ($value) {
                $until = [datetime]::MinValue
                if (-not [datetime]::TryParse([string]$value,[ref]$until)) { throw 'Der Status der Update-Pause ist unklar. Bitte in Windows Update prüfen.' }
                if ($until -gt (Get-Date)) { throw 'Windows-Updates sind pausiert. Öffnen Sie Windows Update, wählen Sie Updates fortsetzen und starten Sie diesen Durchlauf erneut.' }
            }
        }
    }
    $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $au = if (Test-Path $auPath) { Get-ItemProperty $auPath } else { $null }
    if ($au -and $au.UseWUServer -eq 1) { throw 'Ein verwalteter Updateserver ist vorgegeben. Bitte den Firmen-Updateweg verwenden.' }
    $snapshot = [ordered]@{Time=(Get-Date).ToString('o'); NoAutoUpdate=$au.NoAutoUpdate; AUOptions=$au.AUOptions; Services=@()}
    foreach ($name in @('wuauserv','BITS')) {
        $svc = Get-CimInstance Win32_Service -Filter ("Name='"+$name+"'") -ErrorAction Stop
        if (-not $svc) { throw "Der Windows-Dienst $name fehlt. Bitte IT Germany kontaktieren." }
        $snapshot.Services += @{Name=$name; StartMode=$svc.StartMode; State=$svc.State}
    }
    $snapshot | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path (Split-Path $Log) 'Einstellungen-vorher.json') -Encoding UTF8
    $changes = 0
    # Fehlende Werte bedeuten Windows-Standard: automatische Updates. Nicht schreiben.
    if ($null -ne $au -and $null -ne $au.NoAutoUpdate -and $au.NoAutoUpdate -ne 0) {
        Set-ItemProperty $auPath -Name NoAutoUpdate -Value 0 -Type DWord -ErrorAction Stop
        Write-WuLog $Log 'Automatische Windows-Updates aktiviert (NoAutoUpdate: 0).'
        $changes++
    }
    if ($null -ne $au -and $null -ne $au.AUOptions -and $au.AUOptions -ne 4) {
        Set-ItemProperty $auPath -Name AUOptions -Value 4 -Type DWord -ErrorAction Stop
        Write-WuLog $Log 'Automatisches Herunterladen und geplante Installation aktiviert (AUOptions: 4).'
        $changes++
    }
    foreach ($svc in $snapshot.Services) {
        if ($svc.StartMode -eq 'Disabled') {
            Set-Service -Name $svc.Name -StartupType Manual -ErrorAction Stop
            Write-WuLog $Log ($svc.Name + ': deaktivierten Dienst für Windows wieder auf Manuell gesetzt.')
            $changes++
        }
    }
    $after = if (Test-Path $auPath) { Get-ItemProperty $auPath } else { $null }
    if (($null -ne $after.NoAutoUpdate -and $after.NoAutoUpdate -ne 0) -or ($null -ne $after.AUOptions -and $after.AUOptions -ne 4)) {
        throw 'Die Update-Einstellungen konnten nicht bestätigt werden. Bitte Windows Update manuell prüfen.'
    }
    if ($changes -eq 0) { Write-WuLog $Log 'Automatische Updates: Standard oder passende Konfiguration vorhanden. Keine Einstellungen geändert.' }
    else { Write-WuLog $Log ("$changes notwendige Konfigurationsänderung(en) zurückgelesen. Windows übernimmt die Planung selbst.") }
    foreach ($name in @('wuauserv','BITS')) {
        if ((Get-Service $name).Status -ne 'Running') { Start-Service $name -ErrorAction Stop }
    }
}
function Invoke-WindowsCycle([string]$Log) {
    $r = [ordered]@{Task='Windows';Outcome='Attention';Message='';ExitCode=$null;Time=(Get-Date).ToString('o');RebootRequired=$false}
    Ensure-AutomaticWindowsUpdates $Log
    Add-Type -AssemblyName System.Windows.Forms
    if ([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline') { throw 'Bitte das Netzteil anschließen und den Windows-Durchlauf erneut starten.' }
    $system = New-Object -ComObject Microsoft.Update.SystemInfo
    if ($system.RebootRequired) {
        $r.Outcome='RestartNeeded';$r.RebootRequired=$true
        $r.Message='Windows benötigt bereits einen Neustart. Nach dem Neustart erneut nach Updates suchen.'
        return $r
    }
    Write-WuLog $Log 'Windows sucht nach automatisch vorgesehenen Software-Updates. Bitte warten.'
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID='WFW Update-Assistent 1.2'
    $searcher=$session.CreateUpdateSearcher()
    $found=$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software' and AutoSelectOnWebSites=1")
    if ([int]$found.ResultCode -ne 2) { throw 'Die Windows-Updatesuche war nicht vollständig erfolgreich. Bitte erneut versuchen oder Windows Update öffnen.' }
    $installed=0;$failed=0;$skipped=0;$eligible=0
    for ($i=0;$i -lt $found.Updates.Count;$i++) {
        $u=$found.Updates.Item($i)
        $upgrade=$false
        foreach ($category in $u.Categories) { if ($category.CategoryID -eq '3689bdc8-b205-4af4-8d4a-a63924c5e9d5') { $upgrade=$true } }
        # Feature-Upgrades, optionale Vorschauen und interaktive Pakete bleiben manuell.
        if ($upgrade -or $u.BrowseOnly -or $u.InstallationBehavior.CanRequestUserInput) {
            Write-WuLog $Log ('Manuell zu prüfen: '+$u.Title);$skipped++;continue
        }
        $eligible++
        try {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            $collection=New-Object -ComObject Microsoft.Update.UpdateColl
            $null=$collection.Add($u)
            Write-WuLog $Log ('Herunterladen: '+$u.Title)
            $downloader=$session.CreateUpdateDownloader();$downloader.Updates=$collection
            $download=$downloader.Download()
            if ([int]$download.ResultCode -ne 2 -or -not $u.IsDownloaded) { throw 'Download nicht vollständig erfolgreich.' }
            $installer=$session.CreateUpdateInstaller();$installer.Updates=$collection
            if ($installer.IsBusy) { throw 'Eine andere Windows-Installation läuft bereits.' }
            if ($installer.RebootRequiredBeforeInstallation) { $r.RebootRequired=$true;break }
            Write-WuLog $Log ('Installation: '+$u.Title)
            $installation=$installer.Install()
            $one=$installation.GetUpdateResult(0)
            Write-WuLog $Log ("Ergebnis $($one.ResultCode), HRESULT $($one.HResult): $($u.Title)")
            if ([int]$one.ResultCode -eq 2) { $installed++ } else { $failed++ }
            if ($installation.RebootRequired -or $system.RebootRequired) { $r.RebootRequired=$true;break }
        } catch { $failed++;Write-WuLog $Log ('Nicht abgeschlossen: '+$u.Title+' | '+$_.Exception.Message) }
    }
    Write-WuLog $Log ("Installiert: $installed; fehlgeschlagen: $failed; bewusst übersprungen: $skipped.")
    if ($failed -gt 0) {
        $r.Message="$failed Update(s) konnten nicht abgeschlossen werden. Details und Windows Update prüfen."
        if ($r.RebootRequired) { $r.Message+=' Zusätzlich ist ein Neustart nötig; bitte nach dem Speichern selbst neu starten.' }
    } elseif ($r.RebootRequired) {
        $r.Outcome='RestartNeeded'
        $r.Message='Windows benötigt einen Neustart. Nach der Anmeldung öffnet sich der Assistent erneut; dann nochmals nach Updates suchen.'
    } else {
        # Zweite Suche prüft auch Updates, die erst durch den ersten Durchlauf sichtbar wurden.
        $remaining=$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software' and AutoSelectOnWebSites=1")
        if ([int]$remaining.ResultCode -ne 2) { throw 'Die abschließende Updatesuche konnte nicht bestätigt werden.' }
        if ($remaining.Updates.Count -eq 0 -and $skipped -eq 0) {
            $r.Outcome='Done';$r.Message='Durchlauf abgeschlossen. In der geprüften Windows-Update-Auswahl sind keine weiteren Updates offen. Kein Neustart erforderlich.'
        } else {
            $r.Message='Weitere oder manuell zu prüfende Updates sind vorhanden. Starten Sie den Durchlauf erneut und prüfen Sie Windows Update für optionale oder Funktionsupdates.'
        }
    }
    return $r
}
Export-ModuleMember -Function Invoke-WindowsCycle
