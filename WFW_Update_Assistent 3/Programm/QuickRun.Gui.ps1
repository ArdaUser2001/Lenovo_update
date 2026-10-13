# Shared run UI; loaded only by the WPF entry point.
Import-Module (Join-Path $PSScriptRoot 'Module/QuickRun.psm1') -Force -ErrorAction Stop
$script:QuickPlan = $null
$script:QuickActive = $false
$script:QuickStateError = $false
$script:QuickInitializing = $false
$script:QuickPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WFW\Update-Assistent\Gemeinsamer-Durchlauf.json'
$script:QuickText = @{
    de = @{
        Start='Computer aktualisieren'; Continue='Update-Durchlauf fortsetzen'; Title='Computer mit einem Klick aktualisieren'
        Intro='Speichern Sie Ihre Arbeit, schließen Sie andere Programme und verbinden Sie den Computer mit Ladekabel und Internet. Ein Start führt durch Virenschutz, Programmupdates, Windows und passende Treiber.'
        Instructions="1. Speichern Sie Ihre Arbeit und schließen Sie andere Programme.`n2. Schließen Sie das Ladekabel an und stellen Sie die Internetverbindung her.`n3. Klicken Sie auf «Computer aktualisieren». Lesen und bestätigen Sie die Rückfrage.`n`nDer Assistent führt die vier Prüfungen nacheinander aus. Windows kann nach Administratorrechten fragen. Bei einem nötigen Neustart sehen Sie einen Countdown von 120 Sekunden. Nach der Anmeldung am selben Konto geht es automatisch weiter; weitere Administratorabfragen können nötig sein.`n`nStore-Apps und Lenovo-Firmware prüfen Sie anschließend separat. Entfernen von Programmen bleibt freiwillig. Verschieben Sie den Programmordner bis zum Abschluss nicht."
        Optional='Auch eindeutig passende optionale Treiber installieren (optional)'
        OptionalHelp='Ohne Häkchen werden empfohlene Treiber installiert. Mehrdeutige Alternativen sowie BIOS/Firmware bleiben zur manuellen Prüfung.'
        Results='Ergebnisse des gemeinsamen Durchlaufs'; Waiting='Noch nicht gestartet'; Running='Läuft'; Done='Bearbeitet'; Attention='Bitte prüfen'; Restart='Neustart nötig'
        DefenderSecure='Virenschutz'; Install='Programme'; Windows='Windows'; Drivers='Treiber'
        Confirmation="Sind Ihre Arbeit gespeichert, andere Programme geschlossen und das Ladekabel angeschlossen?`n`nDer Assistent aktualisiert Defender, aktiviert unterstützte Schutzfunktionen soweit erlaubt, aktualisiert von winget unterstützte Programme und installiert Windows-Updates und passende Treiber. Paket- und Quellbedingungen werden akzeptiert. Firmenrichtlinien und ein anderer Virenschutz werden respektiert.`n`nBei Bedarf: Neustart nach 120 Sekunden, verschiebbar. Nach Ihrer Anmeldung wird der Durchlauf fortgesetzt. Windows kann Administratorrechte anfordern.`n`nJetzt starten?"
        Finished='Der automatische Durchlauf ist beendet. Lesen Sie die vier Ergebnisse unten. Store-Apps und Lenovo-Firmware bleiben zur separaten Prüfung.'
        NeedsAttention='Der Durchlauf ist beendet; mindestens ein Schritt braucht Ihre Aufmerksamkeit. Lesen Sie die Ergebnisse unten und öffnen Sie bei Bedarf die passenden Windows-Fenster.'
        Interrupted='Ein früherer Durchlauf wurde unterbrochen. Mit der Startschaltfläche können Sie ihn nach Bestätigung fortsetzen.'
        Limit='Nach drei Neustarts wurde der automatische Durchlauf angehalten. Bitte Windows Update prüfen und IT kontaktieren, falls weitere Neustarts verlangt werden.'
        RestartFirst='Bitte zuerst über Start → Ein/Aus → Neu starten neu starten. Danach öffnen Sie den Assistenten wieder und setzen den Durchlauf fort.'
        Postponed='Neustart verschoben. Der Fortschritt ist gespeichert. Starten Sie später selbst neu und öffnen Sie dann den Assistenten zum Fortsetzen.'
        AutoResume='Willkommen zurück. Der gespeicherte Durchlauf wird fortgesetzt.'
    }
    en = @{
        Start='Update my computer'; Continue='Continue update run'; Title='Update your computer with one click'
        Intro='Save your work, close other programs, and connect the charger and internet. One start runs virus protection, application updates, Windows updates and matching drivers.'
        Instructions="1. Save your work and close other programs.`n2. Connect the charger and internet.`n3. Click ""Update my computer"" and confirm the prompt.`n`nThe assistant runs the four checks in sequence. Windows may request administrator approval. If a restart is needed, you see a 120-second countdown. After signing in to the same account, the run continues automatically; further administrator prompts may appear.`n`nCheck Store apps and Lenovo firmware separately afterwards. Removing programs remains optional. Keep the program folder in place until the run finishes."
        Optional='Also install unambiguous optional drivers (optional)'
        OptionalHelp='Without this checkbox, recommended drivers are installed. Ambiguous alternatives and BIOS/firmware require manual review.'
        Results='Results of the combined update run'; Waiting='Not started'; Running='Running'; Done='Processed'; Attention='Please check'; Restart='Restart required'
        DefenderSecure='Virus protection'; Install='Applications'; Windows='Windows'; Drivers='Drivers'
        Confirmation="Have you saved your work, closed other programs and connected the charger?`n`nThe assistant updates Defender, enables supported protection settings where permitted, updates applications supported by winget, and installs Windows updates and matching drivers. Package and source terms are accepted. Company policies and another antivirus product are respected.`n`nIf needed: a restart after 120 seconds, which you can postpone. The run continues after you sign in. Windows may request administrator approval.`n`nStart now?"
        Finished='The automatic run has finished. Read the four results below. Store apps and Lenovo firmware need a separate check.'
        NeedsAttention='The run has finished; at least one step needs your attention. Read the results below and open the appropriate Windows windows if needed.'
        Interrupted='An earlier run was interrupted. Use the start button to confirm and continue it.'
        Limit='The automatic run stopped after three restarts. Check Windows Update and contact IT if more restarts are requested.'
        RestartFirst='Restart through Start → Power → Restart first. Then reopen the assistant to continue.'
        Postponed='Restart postponed. Progress is saved. Restart yourself later, then reopen the assistant to continue.'
        AutoResume='Welcome back. Your saved update run is continuing.'
    }
}
# Make the first screen the combined run while retaining individual tools as alternatives.
foreach ($language in @('de','en')) {
    $t = $script:QuickText[$language]
    $first = $script:StepsByLanguage[$language][0]
    $first.Title = '1 · ' + $t.Title
    $first.Text = $t.Instructions
    $first.Actions = @(@{Id='QuickRun';Label=$t.Start}) + @($first.Actions)
    $script:UiText[$language].StepIntro1 = $t.Intro
}
function Get-QuickText([string]$Key) { [string]$script:QuickText[$script:Language][$Key] }
function Get-QuickBootId { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o') }
function Save-QuickState {
    if ($script:QuickPlan) { Write-QuickRunPlan -Plan $script:QuickPlan -Path $script:QuickPath }
}
function Get-QuickSummary {
    $lines = @()
    foreach ($task in @('DefenderSecure','Install','Windows','Drivers')) {
        $r = @($script:QuickPlan.Results | Where-Object { $_.Task -eq $task } | Select-Object -Last 1)
        $state = Get-QuickText 'Waiting'; $message = ''
        if ($r.Count -gt 0) {
            $state = switch ($r[0].Outcome) { 'Done' {Get-QuickText 'Done'} 'RestartNeeded' {Get-QuickText 'Restart'} default {Get-QuickText 'Attention'} }
            $message = [string]$r[0].Message
        }
        if ($script:QuickActive -and $script:ActiveTask -eq $task) { $state = Get-QuickText 'Running' }
        $lines += ((Get-QuickText $task) + ': ' + $state + $(if ($message) { "`n" + $message }))
    }
    $lines -join "`n`n"
}
function Update-QuickView {
    $visible = ($script:Index -eq 0)
    $script:Ui.QuickOptions.Visibility = if ($visible) {'Visible'} else {'Collapsed'}
    $script:Ui.QuickResults.Visibility = if ($visible -and $script:QuickPlan) {'Visible'} else {'Collapsed'}
    $script:Ui.OptionalDriversText.Text = Get-QuickText 'Optional'
    $script:Ui.QuickOptionsHelp.Text = Get-QuickText 'OptionalHelp'
    $script:Ui.QuickResultsTitle.Text = Get-QuickText 'Results'
    $script:Ui.OptionalDrivers.IsEnabled = -not $script:Busy -and (-not $script:QuickPlan -or $script:QuickPlan.Status -in @('Complete','Paused'))
    if ($script:QuickPlan) {
        $script:Ui.OptionalDrivers.IsChecked = $script:QuickPlan.IncludeOptionalDrivers
        $script:Ui.QuickResultsText.Text = Get-QuickSummary
    }
    # Apply the saved run's status even after a language switch.
    if ($visible -and $script:QuickPlan) {
        if ($script:QuickPlan.Status -eq 'Complete') { $script:Ui.NextHint.Text = Get-QuickText 'Finished' }
        elseif ($script:QuickPlan.Status -eq 'AwaitingRestart' -and -not $script:RestartPending) { $script:Ui.NextHint.Text = Get-QuickText 'RestartFirst' }
        elseif ($script:QuickActive) { $script:Ui.NextHint.Text = (Get-QuickText $script:ActiveTask) + ': ' + (Get-UiText 'Busy') }
    }
}
function Start-QuickRun {
    if ($script:Busy -or $script:QuickStateError) { return }
    try {
        $boot = Get-QuickBootId
        if ($script:QuickPlan -and $script:QuickPlan.Status -eq 'AwaitingRestart' -and $script:QuickPlan.LastBootId -eq $boot) {
            [Windows.MessageBox]::Show((Get-QuickText 'RestartFirst'), (Get-QuickText 'Title')) | Out-Null
            return
        }
        $prompt = Get-QuickText 'Confirmation'
        if ($script:QuickPlan -and $script:QuickPlan.Status -eq 'Running') { $prompt = (Get-QuickText 'Interrupted') + "`n`n" + $prompt }
        if ([Windows.MessageBox]::Show($prompt, (Get-QuickText 'Title'), 'YesNo','Question','No') -ne 'Yes') { return }
        Add-Type -AssemblyName System.Windows.Forms
        if ([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline') { throw 'Bitte zuerst das Ladekabel anschließen. / Please connect the charger first.' }
        if (-not $script:QuickPlan -or $script:QuickPlan.Status -in @('Complete','Paused')) {
            $script:QuickPlan = New-QuickRunPlan -IncludeOptionalDrivers ([bool]$script:Ui.OptionalDrivers.IsChecked) -BootId $boot
            $script:QuickPlan.Language = $script:Language
        } elseif ($script:QuickPlan.Status -eq 'AwaitingRestart') {
            Resume-QuickRunPlan -Plan $script:QuickPlan -BootId $boot
        }
        if ($script:QuickPlan.Status -eq 'Running' -and $script:QuickPlan.CurrentRun -and (Restore-QuickWorker)) { return }
        $script:QuickPlan.LastBootId = $boot
        $script:QuickPlan.RegisteredResume = $false
        Save-QuickState
        Start-QuickNext
    } catch {
        $script:Messages[0] = $_.Exception.Message
        $script:States[0] = 'Bitte prüfen'
        Set-Busy $false
    }
}
# Reattach an existing worker or consume its saved result instead of launching a duplicate.
function Restore-QuickWorker {
    $task = Get-QuickRunTask $script:QuickPlan
    $directory = [IO.Path]::GetFullPath([string]$script:QuickPlan.CurrentRun)
    $allowed = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WFW/Update-Assistent')) + [IO.Path]::DirectorySeparatorChar
    if (-not $directory.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Der gespeicherte Arbeitsordner ist ungültig.' }
    $identityPath = Join-Path $directory 'worker.json'
    $script:CurrentRun = $directory
    $script:ActiveTask = $task
    $script:Index = 0
    $script:Ui.Navigation.SelectedIndex = 0
    if (Test-Path -LiteralPath $identityPath) {
        $identity = Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($identity.Started -is [datetime]) { $identity.Started=$identity.Started.ToUniversalTime().ToString('o') }
        $process = Get-Process -Id ([int]$identity.Id) -ErrorAction SilentlyContinue
        if ($process -and $process.StartTime.ToUniversalTime().ToString('o') -eq $identity.Started -and -not $process.HasExited) {
            $script:ActiveProcess=$process; $script:QuickActive=$true
            Set-Busy $true
            $script:Timer.Start()
            return $true
        }
        if ($process) { $process.Dispose() }
    }
    $resultPath = Join-Path $directory 'result.json'
    if (Test-Path -LiteralPath $resultPath) {
        $result=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:QuickActive=$true
        Complete-QuickWorker $result
        return $true
    }
    # No recorded identity/result after an interruption: stop for manual inspection.
    # Do not risk a second application installer while the original may still be running.
    $script:QuickPlan.Status='Paused'
    $script:QuickPlan.PauseReason='Interrupted'
    Save-QuickState
    throw 'Ein unterbrochener Vorgang hat kein verlässliches Ergebnis geliefert. Bitte laufende Installationen und das Protokoll mit IT prüfen. / An interrupted operation has no reliable result. Check active installers and the log with IT.'
}
function Start-QuickNext {
    if ($script:QuickActive) { return }
    $task = Get-QuickRunTask $script:QuickPlan
    if (-not $task) { return }
    $script:Index = 0
    $script:Ui.Navigation.SelectedIndex = 0
    $script:QuickActive = $true
    Start-Task -Task $task -SkipConfirmation
    Update-QuickView
}
function Complete-QuickWorker($Result) {
    if (-not $Result) {
        $Result = [pscustomobject]@{Task=$script:ActiveTask;Outcome='Attention';Message=(Get-UiText 'ResultMissing');RebootRequired=$false}
    }
    $script:Timer.Stop()
    if ($script:ActiveProcess) { $script:ActiveProcess.Dispose(); $script:ActiveProcess=$null }
    $script:QuickActive = $false
    Set-QuickRunResult -Plan $script:QuickPlan -Result $Result
    $target = @{DefenderSecure=5;Install=3;Windows=0;Drivers=1}[[string]$Result.Task]
    if ($target -ne 0) {
        $script:States[$target] = if ($Result.Outcome -eq 'Done') {'Automatisch bearbeitet'} elseif ($Result.Outcome -eq 'RestartNeeded') {'Neustart nötig'} else {'Bitte prüfen'}
        $script:Messages[$target] = [string]$Result.Message
        $script:DetailLogs[$target] = $script:DetailLogs[0]
    }
    Add-Event ($Result.Task + ': ' + $Result.Message)
    Save-QuickState
    Save-Report
    if ($script:QuickPlan.Status -eq 'Running') { Start-QuickNext; return }
    if ($script:QuickPlan.Status -eq 'AwaitingRestart') {
        $script:States[0]='Neustart nötig'
        $script:Messages[0] = [string]$Result.Message
        Set-Busy $false
        if (-not $script:QuickPlan.ManualRestartOnly) { Begin-RestartCountdown }
        else { $script:Ui.NextHint.Text = Get-QuickText 'RestartFirst' }
    } elseif ($script:QuickPlan.Status -eq 'Paused') {
        $script:States[0]='Bitte prüfen'; $script:Messages[0]=Get-QuickText 'Limit'; Set-Busy $false
    } else {
        $latest = foreach ($task in @('DefenderSecure','Install','Windows','Drivers')) { $script:QuickPlan.Results | Where-Object {$_.Task -eq $task} | Select-Object -Last 1 }
        $attention = @($latest | Where-Object {$_.Outcome -ne 'Done'}).Count -gt 0
        $script:States[0] = if ($attention) {'Bitte prüfen'} else {'Automatisch bearbeitet'}
        $script:Messages[0] = if ($attention) {Get-QuickText 'NeedsAttention'} else {Get-QuickText 'Finished'}
        Set-Busy $false
    }
    Update-QuickView
    Save-Report
}
function Initialize-QuickSession {
    if ($Resume -and -not $ResumeQuickRun) { return }
    $script:QuickInitializing=$true
    try {
        $script:QuickPlan = Read-QuickRunPlan -Path $script:QuickPath
        if (-not $script:QuickPlan) { return }
        $script:Language = $script:QuickPlan.Language
        $script:Steps = $script:StepsByLanguage[$script:Language]
        $script:Ui.LanguageSwitch.SelectedIndex = if ($script:Language -eq 'en') {1} else {0}
        foreach ($task in @('DefenderSecure','Install','Drivers')) {
            $r = $script:QuickPlan.Results | Where-Object {$_.Task -eq $task} | Select-Object -Last 1
            if ($r) {
                $target = @{DefenderSecure=5;Install=3;Drivers=1}[$task]
                $script:States[$target] = if ($r.Outcome -eq 'Done') {'Automatisch bearbeitet'} elseif ($r.Outcome -eq 'RestartNeeded') {'Neustart nötig'} else {'Bitte prüfen'}
                $script:Messages[$target] = [string]$r.Message
            }
        }
        if ($script:QuickPlan.Status -eq 'Complete') {
            $latest = foreach ($task in @('DefenderSecure','Install','Windows','Drivers')) { $script:QuickPlan.Results | Where-Object {$_.Task -eq $task} | Select-Object -Last 1 }
            $attention = @($latest | Where-Object {$_.Outcome -ne 'Done'}).Count -gt 0
            $script:States[0] = if ($attention) {'Bitte prüfen'} else {'Automatisch bearbeitet'}
            $script:Messages[0] = if ($attention) {Get-QuickText 'NeedsAttention'} else {Get-QuickText 'Finished'}
            return
        }
        if ($script:QuickPlan.Status -eq 'AwaitingRestart') {
            $script:States[0]='Neustart nötig'; $script:Messages[0]=Get-QuickText 'Postponed'
            # Auto-resume only a registered restart, a new boot and a recent checkpoint.
            $age = (Get-Date) - [datetime]$script:QuickPlan.ResumeConsentAt
            if ($Resume -and $script:QuickPlan.RegisteredResume -and $age.TotalDays -ge 0 -and $age.TotalDays -le 7 -and
                $script:QuickPlan.LastBootId -ne (Get-QuickBootId)) {
                Resume-QuickRunPlan -Plan $script:QuickPlan -BootId (Get-QuickBootId)
                Save-QuickState
                $script:Window.Add_ContentRendered({ Start-QuickNext })
            }
        } else {
            $script:States[0]='Bitte prüfen'
            $script:Messages[0] = if ($script:QuickPlan.Status -eq 'Paused' -and $script:QuickPlan.PauseReason -eq 'RestartLimit') {Get-QuickText 'Limit'} else {Get-QuickText 'Interrupted'}
        }
    } catch {
        $script:QuickStateError=$true
        $script:States[0]='Bitte prüfen'; $script:Messages[0]=$_.Exception.Message
    } finally { $script:QuickInitializing=$false }
}
