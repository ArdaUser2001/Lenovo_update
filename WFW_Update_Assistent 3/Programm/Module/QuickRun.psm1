# State machine only: no installation, GUI or system changes in this module.
function New-QuickRunPlan {
    param([bool]$IncludeOptionalDrivers = $false, [string]$BootId)
    [pscustomobject]@{
        Version = 1; Id = [guid]::NewGuid().ToString('N'); Stage = 0
        Status = 'Running'; PauseReason = ''; IncludeOptionalDrivers = $IncludeOptionalDrivers
        Results = @(); Restarts = 0; LastBootId = $BootId
        RegisteredResume = $false; ResumeConsentAt = (Get-Date).ToString('o'); ManualRestartOnly = $false
        Language = 'de'; CurrentRun = ''; Updated = (Get-Date).ToString('o')
    }
}
function Get-QuickRunTask {
    param($Plan)
    if ($Plan.Status -eq 'Running' -and $Plan.Stage -ge 0 -and $Plan.Stage -lt 4) {
        @('DefenderSecure','Install','Windows','Drivers')[[int]$Plan.Stage]
    }
}
function Set-QuickRunResult {
    param($Plan, $Result)
    $task = Get-QuickRunTask $Plan
    if (-not $task -or $Result.Task -ne $task -or $Result.Outcome -notin @('Done','Attention','RestartNeeded')) {
        throw 'Unerwartetes Ergebnis im gemeinsamen Update-Durchlauf.'
    }
    $Plan.Results = @($Plan.Results) + @($Result)
    $Plan.CurrentRun = ''
    $Plan.RegisteredResume = $false
    if ($Result.RebootRequired -or $Result.Outcome -eq 'RestartNeeded') {
        $Plan.ManualRestartOnly = ($Result.Outcome -eq 'Attention')
        if ($Plan.Restarts -ge 3) {
            $Plan.Status = 'Paused'
            $Plan.PauseReason = 'RestartLimit'
        } else {
            $Plan.Restarts++
            $Plan.Status = 'AwaitingRestart'
        }
        # The interrupted stage is checked again after reboot; prior stages stay complete.
    } else {
        $Plan.Stage++
        if ($Plan.Stage -ge 4) { $Plan.Status = 'Complete' }
    }
    $Plan.Updated = (Get-Date).ToString('o')
}
function Resume-QuickRunPlan {
    param($Plan, [string]$BootId)
    if ($Plan.Status -ne 'AwaitingRestart' -or $BootId -eq $Plan.LastBootId) {
        throw 'Bitte den Computer zuerst neu starten. Danach kann der Durchlauf fortgesetzt werden.'
    }
    $Plan.Status = 'Running'
    $Plan.LastBootId = $BootId
    $Plan.RegisteredResume = $false
    $Plan.ManualRestartOnly = $false
}
function Write-QuickRunPlan {
    param($Plan, [string]$Path)
    $Plan.Updated = (Get-Date).ToString('o')
    $temporary = $Path + '.tmp'
    $Plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
}
function Read-QuickRunPlan {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $plan = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($plan.Version -ne 1 -or $plan.Id -notmatch '^[a-f0-9]{32}$' -or
        $plan.Stage -notin @(0,1,2,3,4) -or $plan.Restarts -notin @(0,1,2,3) -or
        $plan.Status -notin @('Running','AwaitingRestart','Paused','Complete') -or
        $plan.PauseReason -notin @('','RestartLimit','ResultReadFailed','Interrupted') -or
        $plan.Language -notin @('de','en') -or $plan.IncludeOptionalDrivers -isnot [bool] -or
        $plan.RegisteredResume -isnot [bool] -or $plan.ManualRestartOnly -isnot [bool] -or
        ($plan.Status -in @('Running','AwaitingRestart') -and $plan.Stage -eq 4) -or
        ($plan.Status -eq 'Complete' -and $plan.Stage -ne 4) -or
        [string]::IsNullOrWhiteSpace([string]$plan.LastBootId) -or
        [string]::IsNullOrWhiteSpace([string]$plan.ResumeConsentAt)) {
        throw 'Der gespeicherte Update-Durchlauf ist ungültig. Bitte IT Germany kontaktieren.'
    }
    # PowerShell 7 may deserialize ISO dates to DateTime; Windows PowerShell 5.1 keeps strings.
    if ($plan.LastBootId -is [datetime]) { $plan.LastBootId=$plan.LastBootId.ToUniversalTime().ToString('o') }
    if ($plan.ResumeConsentAt -is [datetime]) { $plan.ResumeConsentAt=$plan.ResumeConsentAt.ToString('o') }
    $parsedConsent = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$plan.ResumeConsentAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsedConsent)) { throw 'Ungültige Wiederaufnahmezeit.' }
    foreach ($r in @($plan.Results)) {
        if ($r.Task -notin @('DefenderSecure','Install','Windows','Drivers') -or $r.Outcome -notin @('Done','Attention','RestartNeeded')) {
            throw 'Der gespeicherte Ergebnisbericht ist ungültig.'
        }
    }
    if ($plan.Status -eq 'Complete') {
        foreach ($task in @('DefenderSecure','Install','Windows','Drivers')) {
            if (@($plan.Results | Where-Object { $_.Task -eq $task }).Count -eq 0) {
                throw 'Der gespeicherte Abschlussbericht ist unvollständig.'
            }
        }
    }
    $plan
}
Export-ModuleMember -Function New-QuickRunPlan,Get-QuickRunTask,Set-QuickRunResult,Resume-QuickRunPlan,Write-QuickRunPlan,Read-QuickRunPlan
