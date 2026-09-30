function Test-LenovoTool([string]$Kind) {
    if ($Kind -eq 'Vantage') {
        $app = Get-AppxPackage -Name 'E046963F.LenovoCompanion' -ErrorAction Stop
        if ($app) { return $true }
        $start = Get-StartApps | Where-Object { $_.Name -match 'Lenovo.*Vantage|Vantage.*Lenovo|^Vantage$' } | Select-Object -First 1
        return [bool]$start
    }
    foreach ($root in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
        if ($root -and (Test-Path -LiteralPath (Join-Path $root 'Lenovo\System Update\tvsu.exe'))) { return $true }
    }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (Test-Path $key) {
            $entry=Get-ItemProperty ($key+'\*') -ErrorAction Stop | Where-Object { $_.DisplayName -match '^(Lenovo )?System Update$' -and $_.Publisher -match 'Lenovo' } | Select-Object -First 1
            if ($entry) { return $true }
        }
    }
    return $false
}
function Install-LenovoTool([string]$Kind,[string]$Log) {
    $r=[ordered]@{Task=('Lenovo'+$Kind);Outcome='Attention';Message='';ExitCode=$null;Time=(Get-Date).ToString('o')}
    $name=if ($Kind -eq 'Vantage') { 'Lenovo Vantage' } else { 'Lenovo System Update' }
    $manufacturer=(Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    if ($manufacturer -notmatch 'Lenovo') { throw 'Die Installation ist für Lenovo-Geräte vorgesehen. Das Gerät wurde nicht als Lenovo erkannt.' }
    if (Test-LenovoTool $Kind) {
        $r.Outcome='ToolReady';$r.Message="$name ist bereits installiert. Keine erneute Installation. Öffnen Sie das Tool und prüfen Sie dort die Geräteupdates."
        return $r
    }
    $winget=Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) { throw 'App-Installer (winget) fehlt. Verwenden Sie die manuelle Installationsquelle im Lenovo-Bereich.' }
    $id=if ($Kind -eq 'Vantage') { '9WZDNCRFJ4MV' } else { 'Lenovo.SystemUpdate' }
    $source=if ($Kind -eq 'Vantage') { 'msstore' } else { 'winget' }
    $arguments=@('install','--id',$id,'--exact','--source',$source,'--silent','--disable-interactivity','--accept-source-agreements','--accept-package-agreements','--no-upgrade')
    "Installation von $name über $source; Paket $id" | Add-Content -LiteralPath $Log -Encoding UTF8
    $ErrorActionPreference='Continue'
    [Console]::OutputEncoding=New-Object System.Text.UTF8Encoding
    & $winget.Source @arguments 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $Log -Encoding UTF8
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $r.ExitCode=$code
    # Paketverfügbarkeit allein ist keine abgeschlossene Firmwareprüfung.
    if ($code -eq 0 -and (Test-LenovoTool $Kind)) {
        $r.Outcome='ToolReady';$r.Message="$name wurde installiert. Klicken Sie jetzt auf Öffnen und folgen Sie der Ersteinrichtung. Prüfen Sie danach im Tool die Geräteupdates."
    } else {
        $r.Message="Die Installation von $name konnte nicht vollständig bestätigt werden (Code $code). Nutzen Sie Details oder die manuelle Installationsquelle. Store-Anmeldung oder Administratorrechte können erforderlich sein."
    }
    return $r
}
Export-ModuleMember -Function @('Test-LenovoTool','Install-LenovoTool')
