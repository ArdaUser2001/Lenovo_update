#requires -Version 5.1
<#
WFW Update-Assistent 1.2 | Ardawan Khosronezhad, IT Germany
Windows PowerShell 5.1 / WPF. Pilotfassung; Windows-Abnahme siehe IT-Testplan.md.
Windows-Durchlauf mit angekündigtem Neustart; keine automatische BIOS-Installation.
#>
[CmdletBinding()]
param(
    [ValidateSet('Gui','Scan','Install','Defender','Windows','LenovoVantage','LenovoSystemUpdate')][string]$Mode = 'Gui',
    [string]$RunDirectory,
    [switch]$Resume
)
$ErrorActionPreference = 'Stop'
$script:ScriptPath = $PSCommandPath
$script:BaseDirectory = $PSScriptRoot

if ($Mode -ne 'Gui') {
    Import-Module (Join-Path $PSScriptRoot 'Module/Updates.psm1') -Force -ErrorAction Stop
    Invoke-Worker -Mode $Mode -RunDirectory $RunDirectory
    exit 0
}

Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
try {
    if ([Environment]::OSVersion.Version.Build -lt 22000) { throw 'Dieser Assistent ist für Windows 11 vorgesehen.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Bitte über UPDATE-ASSISTENT-STARTEN.cmd öffnen.' }
    $script:GuiMutex = New-Object System.Threading.Mutex($false, ('Local\WFW.UpdateAssistent.' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    if (-not $script:GuiMutex.WaitOne(0, $false)) {
        [Windows.MessageBox]::Show('Der Update-Assistent ist bereits geöffnet. Wechseln Sie zum vorhandenen Fenster.','Bereits geöffnet') | Out-Null
        exit 0
    }
    $script:SessionDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('WFW\Update-Assistent\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:SessionDirectory -Force | Out-Null
    $xaml = [xml](Get-Content -LiteralPath (Join-Path $script:BaseDirectory 'Oberflaeche.xaml') -Raw -Encoding UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $script:Window = [Windows.Markup.XamlReader]::Load($reader)
    $area = [Windows.SystemParameters]::WorkArea
    $script:Window.MinWidth = [Math]::Min(700, $area.Width - 24)
    $script:Window.MinHeight = [Math]::Min(480, $area.Height - 24)
    $script:Window.Width = [Math]::Min(1120, $area.Width - 24)
    $script:Window.Height = [Math]::Min(820, $area.Height - 24)
    $script:Ui = @{}
    foreach ($name in @('Logo','Navigation','ProgressText','StepTitle','StepMode','StepText','Actions','Status','Confirm','Details','DetailText','BusyBar','Back','Next','Report','Guide','CancelRestart','OverallProgress','SectionCounter','NextHint','Help')) {
        $script:Ui[$name] = $script:Window.FindName($name)
    }
    $logoPath = Join-Path $script:BaseDirectory 'Assets/Logo.png'
    if (Test-Path -LiteralPath $logoPath) { $script:Ui.Logo.Source = New-Object Windows.Media.Imaging.BitmapImage ([uri]$logoPath) }
} catch {
    [Windows.MessageBox]::Show("Der Assistent konnte nicht gestartet werden.`n`n$($_.Exception.Message)`n`nNutzen Sie die manuelle Anleitung.",'Update-Assistent') | Out-Null
    exit 1
}

$script:Steps = @(
    @{Title='1 · Windows aktualisieren'; Mode='Der Assistent sucht und installiert für Sie'; Text="Willkommen! Gehen Sie die acht Schritte nacheinander durch. Es startet nichts, bevor Sie eine Aktion auswählen und bestätigen.`n`n1. Speichern Sie Ihre Dokumente und schließen Sie andere Programme.`n2. Schließen Sie das Ladekabel an und verbinden Sie den Computer mit dem Internet.`n3. Klicken Sie auf «Windows-Updates starten» und lesen Sie die Rückfrage.`n`nFalls ein Neustart nötig ist, startet der Computer nach 120 Sekunden neu. «Neustart verschieben» stoppt den Countdown. Melden Sie sich danach wieder an und prüfen Sie Windows hier erneut."; Actions=@(@{Id='Windows';Label='Windows-Updates starten'},@{Id='WindowsUpdate';Label='Windows Update selbst öffnen'}); Manual=$false},
    @{Title='2 · Geräte und Treiber'; Mode='Sie prüfen die Angebote in einem Windows-Fenster'; Text="Treiber helfen Windows, Geräte wie Bildschirm, Drucker und Lautsprecher zu verwenden.`n`n1. Klicken Sie auf «Optionale Updates öffnen».`n2. Öffnen Sie dort «Treiberupdates», falls dieser Eintrag angezeigt wird.`n3. Installieren Sie nur Treiber, die Sie benötigen. Sind Sie unsicher, fragen Sie IT Germany.`n4. Warten Sie, bis die Installation beendet ist. Kehren Sie dann hierher zurück und setzen Sie unten das Häkchen.`n`nKeine Treiber angeboten? Dann können Sie die Prüfung ebenfalls bestätigen."; Actions=@(@{Id='Treiber';Label='Optionale Updates öffnen'}); Manual=$true},
    @{Title='3 · Apps aus dem Store'; Mode='Sie aktualisieren Apps im Microsoft Store'; Text="Der Microsoft Store ist das Windows-Programm zum Herunterladen und Aktualisieren von Apps.`n`n1. Klicken Sie auf «Microsoft Store öffnen».`n2. Wählen Sie im Store «Downloads» oder «Bibliothek».`n3. Klicken Sie auf «Updates abrufen» beziehungsweise «Alle aktualisieren», wenn angeboten.`n4. Warten Sie, bis die Updates fertig sind. Kehren Sie hierher zurück und setzen Sie unten das Häkchen.`n`nWenn alle Apps aktuell sind, ist dieser Schritt ebenfalls erledigt."; Actions=@(@{Id='Store';Label='Microsoft Store öffnen'}); Manual=$true},
    @{Title='4 · Andere Programme'; Mode='Erst suchen, dann die Installation starten'; Text="Hier prüft der Assistent weitere unterstützte Programme, zum Beispiel Browser.`n`n1. Klicken Sie auf «1. Nach Updates suchen». Die Suche installiert noch nichts.`n2. Lesen Sie das Ergebnis. Unter «Details zum Vorgang» sehen Sie die Programmliste.`n3. Speichern Sie Ihre Arbeit und schließen Sie die betroffenen Programme.`n4. Klicken Sie auf «2. Programme aktualisieren», sobald die Suche Updates gefunden hat.`n`nDie zweite Schaltfläche bleibt bis dahin grau. Nicht jedes Programm kann automatisch aktualisiert werden."; Actions=@(@{Id='Scan';Label='1. Nach Updates suchen'},@{Id='Install';Label='2. Programme aktualisieren'}); Manual=$false},
    @{Title='5 · Aufräumen (optional)'; Mode='Sie können diesen Schritt auslassen'; Text="Hier können Sie Programme entfernen, die Sie nicht mehr brauchen. Das ist für die Updates nicht erforderlich.`n`n1. Wenn Sie aufräumen möchten, klicken Sie auf «Installierte Apps öffnen».`n2. Suchen Sie ein bekanntes, nicht mehr benötigtes Programm.`n3. Öffnen Sie die drei Punkte daneben und wählen Sie «Deinstallieren».`n`nSie kennen ein Programm nicht? Lassen Sie es installiert.`n`nWenn Sie nichts entfernen möchten, gehen Sie einfach zum nächsten Schritt. Wenn Sie aufgeräumt haben, bestätigen Sie es unten."; Actions=@(@{Id='Apps';Label='Installierte Apps öffnen'},@{Id='ControlPanel';Label='Alternative Programmliste öffnen'}); Manual=$true},
    @{Title='6 · Virenschutz'; Mode='Der Assistent aktualisiert den Windows-Virenschutz'; Text="Microsoft Defender ist der in Windows enthaltene Virenschutz. Neue Schutzinformationen helfen ihm, aktuelle Bedrohungen zu erkennen.`n`n1. Klicken Sie auf «Virenschutz aktualisieren».`n2. Warten Sie auf das Ergebnis unten.`n3. Öffnen Sie danach «Windows-Sicherheit öffnen» und beachten Sie dort angezeigte Hinweise.`n`nNutzen Sie einen anderen Virenschutz? Öffnen Sie stattdessen dessen Programm und aktualisieren Sie ihn dort. Der Assistent wechselt Ihren Virenschutz nicht."; Actions=@(@{Id='Defender';Label='Virenschutz aktualisieren'},@{Id='Security';Label='Windows-Sicherheit öffnen'}); Manual=$false},
    @{Title='7 · Lenovo-Gerät'; Mode='Sie prüfen Geräteupdates im Lenovo-Programm'; Text="Dieser Schritt ist für Computer von Lenovo. Bei einem anderen Hersteller gehen Sie zum nächsten Schritt.`n`n1. Klicken Sie auf «Lenovo Vantage öffnen». Wenn Sie bereits System Update nutzen, öffnen Sie stattdessen dieses Programm.`n2. Fehlt das Programm? Installieren Sie eines der beiden Lenovo-Programme über die passende Schaltfläche. Eines genügt. Öffnen Sie es danach.`n3. Suchen Sie im Lenovo-Programm nach Geräteupdates und folgen Sie dessen Anweisungen.`n4. Kehren Sie nach Abschluss hierher zurück und bestätigen Sie Ihre Prüfung.`n`nBei einem BIOS- oder Firmware-Update wird die Grundsoftware des Computers aktualisiert. Lassen Sie das Ladekabel angeschlossen und schalten Sie den Computer nicht aus. Bei Fragen oder einer BitLocker-Schlüsselabfrage hilft IT Germany."; Actions=@(@{Id='Vantage';Label='Lenovo Vantage öffnen'},@{Id='SystemUpdate';Label='System Update öffnen'},@{Id='LenovoVantage';Label='Vantage installieren, falls es fehlt'},@{Id='LenovoSystemUpdate';Label='System Update installieren, falls es fehlt'},@{Id='LenovoSources';Label='Hilfe bei der Lenovo-Installation'}); Manual=$true},
    @{Title='8 · Zum Abschluss'; Mode='Sie prüfen, ob noch etwas zu tun ist'; Text="1. Klicken Sie auf «Windows Update öffnen». Beachten Sie Hinweise auf weitere Updates oder einen nötigen Neustart.`n2. Falls ein Neustart verlangt wird: Speichern Sie Ihre Arbeit. Klicken Sie unten in Windows auf Start (das Windows-Zeichen), dann auf Ein/Aus und «Neu starten».`n3. Prüfen Sie nach dem Neustart Windows-Updates erneut. Öffnen Sie den Assistenten bei Bedarf wieder über die Startdatei.`n4. Bestätigen Sie unten Ihre Abschlussprüfung. Mit «Zusammenfassung ansehen» öffnen Sie die Ergebnisse dieser Sitzung.`n`nOffene oder fehlgeschlagene Schritte bedeuten, dass noch etwas zu prüfen ist. Die Zusammenfassung ist kein Nachweis, dass der Computer vollständig geschützt ist."; Actions=@(@{Id='WindowsUpdate';Label='Windows Update öffnen'},@{Id='History';Label='Bisherige Updates ansehen'},@{Id='Options';Label='Weitere Windows-Einstellungen'}); Manual=$true}
)
$script:States = @($script:Steps | ForEach-Object { 'Offen' })
$script:Messages = @($script:Steps | ForEach-Object { 'Noch nicht bearbeitet.' })
$script:DetailLogs = @($script:Steps | ForEach-Object { '' })
$script:Index = 0
$script:Busy = $false
$script:ActiveProcess = $null
$script:CurrentRun = $null
$script:ActiveTask = ''
$script:HasScan = $false
$script:NavStatus = @()
$script:Events = New-Object 'System.Collections.Generic.List[string]'

function Add-Event([string]$Message) {
    $script:Events.Add(('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Message))
}

function Save-Report {
    $lines = @('WFW Update-Assistent 1.2', 'Ardawan Khosronezhad | IT Germany', ('Stand: ' + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')), '', 'Diese Angaben gelten nur für diese Sitzung. Manuelle Bestätigungen wurden nicht technisch geprüft.', '')
    for ($i=0; $i -lt $script:Steps.Count; $i++) { $lines += ($script:Steps[$i].Title + ': ' + $script:States[$i]); $lines += $script:Messages[$i]; $lines += '' }
    $lines += 'Ablauf:'; $lines += $script:Events.ToArray()
    $lines | Set-Content -LiteralPath (Join-Path $script:SessionDirectory 'Zusammenfassung.txt') -Encoding UTF8
}

function Refresh-Progress {
    $done = @($script:States | Where-Object { $_ -eq 'Benutzer bestätigt' -or $_ -eq 'Automatisch bearbeitet' }).Count
    for ($i=0; $i -lt $script:NavStatus.Count; $i++) { $script:NavStatus[$i].Text = $script:States[$i] }
    $script:Ui.OverallProgress.Value = $done
    $script:Ui.ProgressText.Text = "$done von 8 Bereichen bearbeitet · "
}

function Show-Step {
    $step = $script:Steps[$script:Index]
    $script:Ui.StepTitle.Text = $step.Title
    $script:Ui.StepMode.Text = $step.Mode
    $script:Ui.StepText.Text = $step.Text
    $script:Ui.Status.Text = $script:Messages[$script:Index]
    $script:Ui.DetailText.Text = $script:DetailLogs[$script:Index]
    $script:Ui.Confirm.Visibility = if ($step.Manual) { 'Visible' } else { 'Collapsed' }
    $script:Ui.Confirm.IsChecked = ($script:States[$script:Index] -eq 'Benutzer bestätigt')
    $script:Ui.Actions.Children.Clear()
    $primaryAction = if ($script:Index -eq 3 -and $script:HasScan) { 'Install' } else { $step.Actions[0].Id }
    foreach ($action in $step.Actions) {
        $button = New-Object Windows.Controls.Button
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $action.Label
        $label.TextWrapping = 'Wrap'
        $button.Content = $label; $button.Tag = $action.Id
        $button.MaxWidth = 280
        [Windows.Automation.AutomationProperties]::SetName($button, $action.Label)
        if ($action.Id -ne $primaryAction) { $button.Style = $script:Window.FindResource('SecondaryButtonStyle') }
        if ($action.Id -eq 'Install') { $button.IsEnabled = $script:HasScan }
        $button.Add_Click({ param($sender,$eventArgs) Invoke-StepAction ([string]$sender.Tag) })
        $script:Ui.Actions.Children.Add($button) | Out-Null
    }
    $script:Ui.Back.IsEnabled = ($script:Index -gt 0)
    $completed = $script:States[$script:Index] -in @('Benutzer bestätigt','Automatisch bearbeitet')
    $script:Ui.Next.Content = if ($script:Index -eq 7) { 'Zusammenfassung ansehen' } elseif ($completed) { 'Nächster Schritt →' } else { 'Weiter (bleibt offen) →' }
    $script:Ui.NextHint.Text = if ($completed) {
        'Dieser Schritt ist bearbeitet. Sie können zum nächsten Schritt gehen.'
    } elseif ($script:States[$script:Index] -eq 'Suche abgeschlossen') {
        'Lesen Sie die Programmliste unter «Details zum Vorgang». Starten Sie danach «2. Programme aktualisieren».'
    } elseif ($step.Manual) {
        'Erledigen Sie die Prüfung im geöffneten Fenster. Kehren Sie hierher zurück und setzen Sie erst dann das Häkchen. Weitergehen allein bestätigt nichts.'
    } else {
        'Beginnen Sie mit der hervorgehobenen Schaltfläche oben. Lesen Sie danach das Ergebnis hier. Weitergehen allein bestätigt nichts.'
    }
    if ($script:Index -eq 7) { $script:Ui.NextHint.Text += ' Die Zusammenfassung zeigt auch Schritte, die noch offen sind.' }
    $script:Ui.SectionCounter.Text = 'SCHRITT ' + ($script:Index + 1) + ' VON 8'
    Refresh-Progress
}

function Open-Target([string]$Target, [string]$Text) {
    try {
        Start-Process -FilePath $Target -ErrorAction Stop | Out-Null
        $script:Messages[$script:Index] = $Text
        Add-Event $Text
        Show-Step
    } catch {
        [Windows.MessageBox]::Show("Das Fenster konnte nicht geöffnet werden. Nutzen Sie den entsprechenden Abschnitt in der Anleitung.`n`n$($_.Exception.Message)",'Bitte manuell öffnen') | Out-Null
    }
}

function Set-Busy([bool]$Value) {
    $script:Busy = $Value
    foreach ($key in @('Navigation','Actions','Back','Next','Confirm')) { $script:Ui[$key].IsEnabled = -not $Value }
    $script:Ui.BusyBar.Visibility = if ($Value) { 'Visible' } else { 'Collapsed' }
    if ($Value) { $script:Ui.NextHint.Text = 'Bitte warten und den Assistenten geöffnet lassen. Sie müssen nicht erneut klicken.' }
    if (-not $Value) { Show-Step }
}

function Start-Task([string]$Task) {
    if ($script:Busy) { return }
    if ($Task -in @('LenovoVantage','LenovoSystemUpdate')) {
        $name = if ($Task -eq 'LenovoVantage') { 'Lenovo Vantage' } else { 'Lenovo System Update' }
        $choice = [Windows.MessageBox]::Show(($name + ' wird nur installiert, wenn es noch fehlt. Die Paket- und Quellbedingungen werden akzeptiert. Bei Microsoft Store wird die Geräteregion an den Dienst übermittelt. Administratorrechte oder Store-Anmeldung können erforderlich sein. Es genügt eines der beiden Tools. Fortfahren?'), 'Lenovo-Tool installieren', 'YesNo', 'Question')
    } elseif ($Task -eq 'Windows') {
        $choice = [Windows.MessageBox]::Show("Haben Sie Ihre Arbeit gespeichert und andere Programme geschlossen?`n`nNach «Ja» sucht und installiert der Assistent passende Windows-Updates. Auf nicht zentral verwalteten Geräten passt er bei Bedarf lokale Update-Einstellungen an. Dabei werden die Lizenzbedingungen der Updates akzeptiert.`n`nFalls nötig, startet der Computer nach einem Countdown von 120 Sekunden neu. Mit «Neustart verschieben» können Sie den Countdown stoppen.`n`nJetzt starten?", 'Windows aktualisieren und bei Bedarf neu starten', 'YesNo', 'Question')
    } elseif ($Task -eq 'Scan') {
        $choice = [Windows.MessageBox]::Show('Die Suche verwendet Microsofts öffentliche winget-Quelle und akzeptiert deren Quellbedingungen. Es werden noch keine Programme installiert. Fortfahren?', 'Nach Programmupdates suchen', 'YesNo', 'Question')
    } elseif ($Task -eq 'Install') {
        $choice = [Windows.MessageBox]::Show('Alle von winget unterstützten, aktualisierbaren Programme werden aktualisiert. Dabei werden die Paket-Lizenzbedingungen automatisch akzeptiert. Fahren Sie nur fort, wenn Sie dazu berechtigt sind. Speichern und schließen Sie vorher alle offenen Programme. Installation starten?', 'Programmupdates starten', 'YesNo', 'Question')
    } else {
        $choice = [Windows.MessageBox]::Show('Die Schutzinformationen des Windows-Virenschutzes werden aktualisiert. Windows kann fragen, ob Änderungen am Computer erlaubt sind. Wenn Ihnen die nötigen Rechte fehlen, wählen Sie Nein und wenden Sie sich an IT Germany. Jetzt starten?', 'Defender aktualisieren', 'YesNo', 'Question')
    }
    if ($choice -ne 'Yes') { return }
    try {
        $script:CurrentRun = Join-Path $script:SessionDirectory ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:CurrentRun | Out-Null
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Vollständige Pfade in doppelten Anführungszeichen; keine dynamischen Befehle.
        $argumentLine = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "{0}" -Mode {1} -RunDirectory "{2}"' -f $script:ScriptPath,$Task,$script:CurrentRun
        $parameters = @{FilePath=$exe; ArgumentList=$argumentLine; PassThru=$true; WindowStyle='Hidden'; ErrorAction='Stop'}
        if ($Task -in @('Defender','Windows')) {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal $identity
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { $parameters.Verb = 'RunAs' }
        }
        $script:ActiveProcess = Start-Process @parameters
        $script:ActiveTask = $Task
        if ($Task -eq 'Scan') { $script:HasScan = $false }
        $script:States[$script:Index] = 'Läuft'
        $script:Messages[$script:Index] = 'Bitte warten. Der Vorgang kann mehrere Minuten dauern. Lassen Sie den Assistenten geöffnet.'
        $script:Ui.Status.Text = $script:Messages[$script:Index]
        $script:DetailLogs[$script:Index] = ''
        $script:Ui.DetailText.Text = ''
        Add-Event ("$Task gestartet.")
        Set-Busy $true
        $script:Timer.Start()
    } catch {
        $script:States[$script:Index] = 'Offen'
        $script:Messages[$script:Index] = 'Der Vorgang wurde nicht gestartet oder die Administratorabfrage wurde abgebrochen. Sie können erneut starten oder die manuelle Anleitung verwenden.'
        Add-Event ($script:Messages[$script:Index] + ' ' + $_.Exception.Message)
        Set-Busy $false
    }
}

function Open-Lenovo([string]$Kind) {
    try {
        if ($Kind -eq 'SystemUpdate') {
            $locations = @()
            foreach ($root in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
                if ($root) { $locations += (Join-Path $root 'Lenovo\System Update\tvsu.exe') }
            }
            $target = $locations | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
            if (-not $target) { throw 'Lenovo System Update wurde nicht gefunden. Öffnen Sie Lenovo Vantage über das Startmenü oder verwenden Sie die manuelle Anleitung.' }
            # Ausschließlich Benutzeroberfläche starten, keine Installationsparameter.
            Start-Process -FilePath $target -ErrorAction Stop | Out-Null
        } else {
            $app = Get-StartApps | Where-Object { $_.Name -match 'Lenovo.*Vantage|Vantage.*Lenovo|^Vantage$' } | Select-Object -First 1
            if (-not $app) { throw 'Lenovo Vantage wurde nicht gefunden. Suchen Sie im Startmenü nach «Lenovo Vantage» oder nutzen Sie Lenovo System Update.' }
            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"shell:AppsFolder\' + $app.AppID + '"') -ErrorAction Stop | Out-Null
        }
        $script:Messages[$script:Index] = 'Lenovo-Programm zum Öffnen angefordert. Suchen und installieren Sie dort die passenden Updates. Anschließend hier bestätigen.'
        Add-Event $script:Messages[$script:Index]
        Show-Step
    } catch {
        [Windows.MessageBox]::Show($_.Exception.Message,'Lenovo-Programm manuell öffnen') | Out-Null
    }
}

function Invoke-StepAction([string]$Action) {
    switch ($Action) {
        'Windows' { Start-Task 'Windows' }
        'Scan' { Start-Task 'Scan' }
        'Install' { Start-Task 'Install' }
        'Defender' { Start-Task 'Defender' }
        'Treiber' { Open-Target 'ms-settings:windowsupdate-optionalupdates' 'Fenster angefordert. Treiber bitte dort auswählen und installieren; danach hier bestätigen.' }
        'Store' { Open-Target 'ms-windows-store://home' 'Store angefordert. Unter Downloads oder Bibliothek Updates abrufen und abschließen; danach hier bestätigen.' }
        'Apps' { Open-Target 'ms-settings:appsfeatures' 'Installierte Apps angefordert. Nur bekannte, nicht mehr benötigte Programme selbst entfernen.' }
        'ControlPanel' { Open-Target (Join-Path $env:SystemRoot 'System32\appwiz.cpl') 'Programme und Features angefordert. Gewünschte Programme selbst auswählen.' }
        'Security' { Open-Target 'ms-settings:windowsdefender' 'Windows-Sicherheit angefordert. Öffnen Sie Windows-Sicherheit und prüfen Sie die angezeigten Hinweise.' }
        'LenovoVantage' { Start-Task 'LenovoVantage' }
        'LenovoSystemUpdate' { Start-Task 'LenovoSystemUpdate' }
        'LenovoSources' {
            $answer = [Windows.MessageBox]::Show('Ja: Lenovo Vantage im Microsoft Store öffnen. Nein: offizielle Lenovo-Downloadseite für System Update öffnen. Abbrechen: zurück.', 'Manuell installieren', 'YesNoCancel', 'Question')
            if ($answer -eq 'Yes') { Open-Target 'ms-windows-store://pdp/?ProductId=9WZDNCRFJ4MV' 'Vantage-Storeseite angefordert. Dort Installieren wählen; anschließend hier Vantage öffnen.' }
            elseif ($answer -eq 'No') { Open-Target 'https://support.lenovo.com/downloads/ds012808' 'Lenovo-Downloadseite angefordert. Kompatibilität prüfen, Installer herunterladen und ausführen; danach hier System Update öffnen.' }
        }
        'Vantage' { Open-Lenovo 'Vantage' }
        'SystemUpdate' { Open-Lenovo 'SystemUpdate' }
        'WindowsUpdate' { Open-Target 'ms-settings:windowsupdate' 'Windows Update angefordert. Suchen Sie nach Updates und beachten Sie ausstehende Neustarts.' }
        'History' { Open-Target 'ms-settings:windowsupdate-history' 'Updateverlauf angefordert. Prüfen Sie, ob Updates fehlgeschlagen sind.' }
        'Options' { Open-Target 'ms-settings:windowsupdate-options' 'Erweiterte Optionen angefordert. Prüfen Sie dort Ihre gewünschten Einstellungen.' }
    }
}

$script:Timer = New-Object Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromSeconds(1)
$script:Timer.Add_Tick({
    try {
        $logPath = Join-Path $script:CurrentRun 'details.txt'
        if (Test-Path -LiteralPath $logPath) {
            $script:DetailLogs[$script:Index] = (Get-Content -LiteralPath $logPath -Encoding UTF8 -Tail 160 -ErrorAction SilentlyContinue) -join "`r`n"
            $script:Ui.DetailText.Text = $script:DetailLogs[$script:Index]
        }
        if ($script:ActiveProcess.HasExited) {
            $script:Timer.Stop()
            $result = $null
            $resultFile = Join-Path $script:CurrentRun 'result.json'
            if (Test-Path -LiteralPath $resultFile) {
                $result = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $script:Messages[$script:Index] = [string]$result.Message
                $script:States[$script:Index] = switch ($result.Outcome) {
                    'Done' { 'Automatisch bearbeitet' }
                    'Scanned' { 'Suche abgeschlossen' }
                    'ToolReady' { 'Programm bereit' }
                    'RestartNeeded' { 'Neustart nötig' }
                    default { 'Bitte prüfen' }
                }
                if ($script:ActiveTask -eq 'Scan') { $script:HasScan = ($result.Outcome -eq 'Scanned') }
            } else {
                $script:States[$script:Index] = 'Bitte prüfen'
                $script:Messages[$script:Index] = 'Der Vorgang lieferte kein Ergebnis. Möglicherweise blockiert eine Richtlinie die Ausführung. Nutzen Sie die manuelle Anleitung; bei wiederholtem Fehler hilft IT Germany.'
            }
            Add-Event ($script:ActiveTask + ': ' + $script:Messages[$script:Index])
            $script:ActiveProcess.Dispose()
            $script:ActiveProcess = $null
            Set-Busy $false
            Save-Report
            if ($script:ActiveTask -eq 'Windows' -and $result -and $result.Outcome -eq 'RestartNeeded') { Begin-RestartCountdown }
        }
    } catch {
        $script:Timer.Stop()
        # Den Installationsprozess nicht beenden. Bis zu seinem Ende gesperrt bleiben.
        if ($script:ActiveProcess -and -not $script:ActiveProcess.HasExited) {
            $script:Ui.Status.Text = 'Der Vorgang läuft noch. Die Meldungen können vorübergehend nicht gelesen werden.'
            $script:Timer.Start()
        } else {
            $script:States[$script:Index] = 'Bitte prüfen'
            $script:Messages[$script:Index] = 'Das Ergebnis konnte nicht gelesen werden. Prüfen Sie den Zustand über die manuelle Anleitung.'
            Set-Busy $false
        }
    }
})

$script:RestartPending = $false
$script:ResumePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WFW\Update-Assistent\Fortsetzen.json'
$script:RestartTimer = New-Object Windows.Threading.DispatcherTimer
$script:RestartTimer.Interval = [TimeSpan]::FromSeconds(1)
function Restore-Session {
    if (Test-Path -LiteralPath $script:ResumePath) {
        try {
            $saved = Get-Content -LiteralPath $script:ResumePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.States.Count -eq 8 -and $saved.Messages.Count -eq 8) {
                $script:States = @($saved.States)
                $script:Messages = @($saved.Messages)
                $script:States[0] = 'Offen'
                $script:Messages[0] = 'Willkommen zurück. Bitte Windows erneut prüfen, damit nachgelagerte Updates ebenfalls installiert werden.'
            }
            Remove-Item -LiteralPath $script:ResumePath -Force
        } catch { $script:Messages[0] = 'Bitte Windows-Updates erneut prüfen. Die frühere Sitzung konnte nicht übernommen werden.' }
    }
}
function Stop-RestartCountdown {
    $script:RestartTimer.Stop()
    $script:RestartPending = $false
    $script:Ui.CancelRestart.Visibility = 'Collapsed'
    $script:Messages[0] = 'Neustart verschoben. Speichern Sie Ihre Arbeit und starten Sie den Rechner später selbst neu. Danach Windows erneut prüfen.'
    $script:States[0] = 'Neustart nötig'
    Set-Busy $false
    Add-Event 'Der Benutzer hat den automatischen Neustart verschoben.'
    Save-Report
}
function Begin-RestartCountdown {
    $script:RestartDeadline = (Get-Date).AddSeconds(120)
    $script:RestartPending = $true
    Set-Busy $true
    $script:Ui.BusyBar.Visibility = 'Collapsed'
    $script:Ui.CancelRestart.Visibility = 'Visible'
    $script:Ui.Status.Text = 'Windows startet in 120 Sekunden neu. Speichern und schließen Sie Ihre Arbeit. Sie können den Neustart verschieben.'
    $script:Window.WindowState = 'Normal'
    $script:Window.Activate() | Out-Null
    $script:RestartTimer.Start()
}
$script:RestartTimer.Add_Tick({
    try {
        $left = [int][Math]::Ceiling(($script:RestartDeadline - (Get-Date)).TotalSeconds)
        if ($left -gt 0) {
            $script:Ui.Status.Text = "Automatischer Neustart in $left Sekunden. Bitte Arbeit speichern. Mit «Neustart verschieben» stoppen Sie den Countdown."
            return
        }
        $script:RestartTimer.Stop()
        @{States=$script:States;Messages=$script:Messages;Time=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ResumePath -Encoding UTF8
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $command = '"{0}" -NoProfile -STA -ExecutionPolicy RemoteSigned -File "{1}" -Resume' -f $exe,$script:ScriptPath
        # RunOnce ist auf 260 Zeichen begrenzt. Keine stille, unzuverlässige Registrierung.
        if ($command.Length -gt 260) { throw 'Der Programmpfad ist zu lang für die automatische Wiederaufnahme. Bitte Paket in einen kürzeren Ordner verschieben oder manuell neu starten.' }
        $runOnce='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        if (-not (Test-Path $runOnce)) { New-Item $runOnce -Force | Out-Null }
        New-ItemProperty -Path $runOnce -Name WFWUpdateAssistant -Value $command -PropertyType String -Force | Out-Null
        Save-Report
        # Eigener Countdown statt shutdown /t 120: /t > 0 würde /f implizieren.
        # /t 0 ohne /f lässt Anwendungen den Neustart blockieren.
        & (Join-Path $env:SystemRoot 'System32\shutdown.exe') /r /t 0 /d p:2:17
        if ($LASTEXITCODE -ne 0) { throw 'Windows konnte den Neustart nicht starten. Bitte speichern und über das Startmenü selbst neu starten.' }
        $script:RestartPending = $false
        $script:Ui.CancelRestart.Visibility = 'Collapsed'
        $script:Messages[0] = 'Neustart an Windows übergeben. Falls eine Anwendung ihn blockiert, speichern und schließen Sie diese. Danach gegebenenfalls über Start neu starten.'
        Set-Busy $false
    } catch {
        $script:RestartPending = $false
        $script:Ui.CancelRestart.Visibility = 'Collapsed'
        $script:States[0] = 'Bitte prüfen'
        $script:Messages[0] = $_.Exception.Message
        Set-Busy $false
    }
})
$script:Ui.CancelRestart.Add_Click({ Stop-RestartCountdown })

$script:NavStatus = @()
foreach ($step in $script:Steps) {
    $item = New-Object Windows.Controls.ListBoxItem
    $stack = New-Object Windows.Controls.StackPanel
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $step.Title
    $title.FontWeight = 'SemiBold'
    $title.TextWrapping = 'Wrap'
    $caption = New-Object Windows.Controls.TextBlock
    $caption.Text = 'Offen'
    $caption.FontSize = 11
    $caption.Margin = '0,4,0,0'
    $caption.TextWrapping = 'Wrap'
    $stack.Children.Add($title) | Out-Null
    $stack.Children.Add($caption) | Out-Null
    $item.Content = $stack
    $script:Ui.Navigation.Items.Add($item) | Out-Null
    $script:NavStatus += $caption
}
$script:Ui.Navigation.Add_SelectionChanged({
    if ($script:Ui.Navigation.SelectedIndex -ge 0 -and -not $script:Busy) {
        $script:Index = $script:Ui.Navigation.SelectedIndex
        Show-Step
    }
})
$script:Ui.Confirm.Add_Click({
    $script:States[$script:Index] = if ($script:Ui.Confirm.IsChecked) { 'Benutzer bestätigt' } else { 'Offen' }
    $script:Messages[$script:Index] = if ($script:Ui.Confirm.IsChecked) { 'Von Ihnen als geprüft bestätigt. Der Assistent hat diesen Schritt nicht technisch überprüft.' } else { 'Noch nicht bestätigt.' }
    Add-Event ($script:Steps[$script:Index].Title + ': ' + $script:States[$script:Index])
    Show-Step
    Save-Report
})
$script:Ui.Back.Add_Click({ if ($script:Index -gt 0) { $script:Ui.Navigation.SelectedIndex-- } })
$script:Ui.Next.Add_Click({
    if ($script:Index -lt 7) { $script:Ui.Navigation.SelectedIndex++ }
    else { Save-Report; Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"' + (Join-Path $script:SessionDirectory 'Zusammenfassung.txt') + '"') }
})
$script:Ui.Help.Add_Click({
    [Windows.MessageBox]::Show("So verwenden Sie den Assistenten:`n`n• Beginnen Sie oben mit der farbigen Schaltfläche. Lesen Sie danach den aktuellen Stand.`n• Öffnet sich ein anderes Fenster, erledigen Sie dort die beschriebenen Schritte.`n• Zurück zum Assistenten: Klicken Sie auf sein Symbol unten in der Windows-Taskleiste. Oder halten Sie Alt gedrückt und drücken Sie Tab, bis der Assistent ausgewählt ist.`n• Eine graue Schaltfläche ist gerade nicht verfügbar. Warten Sie auf den laufenden Vorgang oder führen Sie zuerst die Suche aus.`n• Fragt Windows, ob Änderungen erlaubt sind? Prüfen Sie, ob die Abfrage zu Ihrer gerade gestarteten Aktion gehört. Wenn Ihnen die nötigen Rechte fehlen oder Sie unsicher sind, wählen Sie Nein und fragen Sie IT Germany.`n• Weitergehen markiert einen Schritt nicht als erledigt. Offene Schritte sehen Sie links.`n`nBei Problemen: Notieren Sie die Meldung. Über «Protokoll für IT» können Sie die Ergebnisdateien öffnen; es wird nichts automatisch versendet.", 'Hilfe zur Bedienung', 'OK', 'Information') | Out-Null
})
$script:Ui.Report.Add_Click({
    try { Save-Report; Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $script:SessionDirectory + '"') }
    catch { [Windows.MessageBox]::Show('Das Protokoll konnte nicht geöffnet werden.','Protokoll') | Out-Null }
})
$script:Ui.Guide.Add_Click({
    $path = Join-Path (Split-Path $script:BaseDirectory) 'Anleitung.pdf'
    if (Test-Path -LiteralPath $path) {
        try { Start-Process -FilePath $path -ErrorAction Stop | Out-Null }
        catch { [Windows.MessageBox]::Show('Die PDF konnte nicht geöffnet werden. Öffnen Sie Anleitung.pdf im entpackten Ordner.','Anleitung') | Out-Null }
    }
    else { [Windows.MessageBox]::Show('Öffnen Sie die separat mitgelieferte PDF-Anleitung.','Anleitung') | Out-Null }
})
$script:Window.Add_Closing({ param($sender,$eventArgs)
    if ($script:RestartPending) { Stop-RestartCountdown }
    if ($script:Busy) {
        $eventArgs.Cancel = $true
        [Windows.MessageBox]::Show('Ein Update-Vorgang läuft noch. Bitte warten Sie, bis er beendet ist. Sie können dieses Fenster währenddessen minimieren.','Vorgang läuft') | Out-Null
    } else { $script:Timer.Stop(); try { Save-Report } catch { } }
})
if ($Resume) { Restore-Session }
$script:Ui.Navigation.SelectedIndex = 0
Add-Event 'Assistent gestartet. Keine Updates automatisch gestartet.'
Save-Report
try { $script:Window.ShowDialog() | Out-Null } finally { $script:GuiMutex.ReleaseMutex(); $script:GuiMutex.Dispose() }
