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

# Worker entry point: return before loading WPF when invoked for a background task.
if ($Mode -ne 'Gui') {
    Import-Module (Join-Path $PSScriptRoot 'Module/Updates.psm1') -Force -ErrorAction Stop
    Invoke-Worker -Mode $Mode -RunDirectory $RunDirectory
    exit 0
}

# GUI startup: load WPF resources, create a session folder and bind named controls.
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
# Read a XAML file and instantiate its WPF controls or resource dictionary.
function Load-XamlDocument([string]$Path) {
    $xml = [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $xml
    [Windows.Markup.XamlReader]::Load($reader)
}
try {
    if ([Environment]::OSVersion.Version.Build -lt 22000) {
        throw 'Dieser Assistent ist für Windows 11 vorgesehen.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'Bitte über UPDATE-ASSISTENT-STARTEN.cmd öffnen.'
    }
    $script:GuiMutex = New-Object System.Threading.Mutex($false, ('Local\WFW.UpdateAssistent.' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    if (-not $script:GuiMutex.WaitOne(0, $false)) {
        [Windows.MessageBox]::Show('Der Update-Assistent ist bereits geöffnet. Wechseln Sie zum vorhandenen Fenster.','Bereits geöffnet') | Out-Null
        exit 0
    }
    $script:SessionDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('WFW\Update-Assistent\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:SessionDirectory -Force | Out-Null
    if (-not [Windows.Application]::Current) {
        $null = New-Object Windows.Application
    }
    foreach ($dictionary in @('Icons.xaml','Theme.xaml','Styles.xaml')) {
        [Windows.Application]::Current.Resources.MergedDictionaries.Add((Load-XamlDocument (Join-Path $script:BaseDirectory ('Oberflaeche\' + $dictionary)))) | Out-Null
    }
    $script:Window = Load-XamlDocument (Join-Path $script:BaseDirectory 'Oberflaeche.xaml')
    $area = [Windows.SystemParameters]::WorkArea
    $script:Window.MinWidth = [Math]::Min(700, $area.Width - 24)
    $script:Window.MinHeight = [Math]::Min(480, $area.Height - 24)
    $script:Window.Width = [Math]::Min(1120, $area.Width - 24)
    $script:Window.Height = [Math]::Min(820, $area.Height - 24)
    $script:Ui = @{
    }
    foreach ($name in @('Logo','Navigation','ProgressText','StepTitle','StepMode','StepText','Actions','Status','Confirm','Details','DetailText','BusyBar','Back','Next','Report','Guide','CancelRestart','OverallProgress','SectionCounter','NextHint','Help','AppTitle','AppSubtitle','LanguageLabel','LanguageSwitch','ProgressLabel','CurrentStatusLabel','NextActionLabel','StatusIcon','ConfirmText','HelpText','FooterText','StepIntro','Instructions','Alternatives','AdditionalActions','Support')) {
        $script:Ui[$name] = $script:Window.FindName($name)
    }
    $logoPath = Join-Path $script:BaseDirectory 'Assets/Logo.png'
    if (Test-Path -LiteralPath $logoPath) {
        $script:Ui.Logo.Source = New-Object Windows.Media.Imaging.BitmapImage ([uri]$logoPath)
    }
} catch {
    [Windows.MessageBox]::Show("Der Assistent konnte nicht gestartet werden.`n`n$($_.Exception.Message)`n`nNutzen Sie die manuelle Anleitung.",'Update-Assistent') | Out-Null
    exit 1
}

# Step definitions: stable action IDs connect localized labels to Invoke-StepAction.
$script:Steps = @(
    @{
        Title = '1 · Windows aktualisieren';
        Mode = 'Der Assistent sucht und installiert für Sie';
        Text = "Willkommen! Gehen Sie die acht Schritte nacheinander durch. Es startet nichts, bevor Sie eine Aktion auswählen und bestätigen.`n`n1. Speichern Sie Ihre Dokumente und schließen Sie andere Programme.`n2. Schließen Sie das Ladekabel an und verbinden Sie den Computer mit dem Internet.`n3. Klicken Sie auf «Windows-Updates starten» und lesen Sie die Rückfrage.`n`nFalls ein Neustart nötig ist, startet der Computer nach 120 Sekunden neu. «Neustart verschieben» stoppt den Countdown. Melden Sie sich danach wieder an und prüfen Sie Windows hier erneut.";
        Actions = @(@{
            Id = 'Windows';
            Label = 'Windows-Updates starten'
        },@{
            Id = 'WindowsUpdate';
            Label = 'Windows Update selbst öffnen'
        });
        Manual = $false
    },
    @{
        Title = '2 · Geräte und Treiber';
        Mode = 'Sie prüfen die Angebote in einem Windows-Fenster';
        Text = "Treiber helfen Windows, Geräte wie Bildschirm, Drucker und Lautsprecher zu verwenden.`n`n1. Klicken Sie auf «Optionale Updates öffnen».`n2. Öffnen Sie dort «Treiberupdates», falls dieser Eintrag angezeigt wird.`n3. Installieren Sie nur Treiber, die Sie benötigen. Sind Sie unsicher, fragen Sie IT Germany.`n4. Warten Sie, bis die Installation beendet ist. Kehren Sie dann hierher zurück und setzen Sie unten das Häkchen.`n`nKeine Treiber angeboten? Dann können Sie die Prüfung ebenfalls bestätigen.";
        Actions = @(@{
            Id = 'Treiber';
            Label = 'Optionale Updates öffnen'
        });
        Manual = $true
    },
    @{
        Title = '3 · Apps aus dem Store';
        Mode = 'Sie aktualisieren Apps im Microsoft Store';
        Text = "Der Microsoft Store ist das Windows-Programm zum Herunterladen und Aktualisieren von Apps.`n`n1. Klicken Sie auf «Microsoft Store öffnen».`n2. Wählen Sie im Store «Downloads» oder «Bibliothek».`n3. Klicken Sie auf «Updates abrufen» beziehungsweise «Alle aktualisieren», wenn angeboten.`n4. Warten Sie, bis die Updates fertig sind. Kehren Sie hierher zurück und setzen Sie unten das Häkchen.`n`nWenn alle Apps aktuell sind, ist dieser Schritt ebenfalls erledigt.";
        Actions = @(@{
            Id = 'Store';
            Label = 'Microsoft Store öffnen'
        });
        Manual = $true
    },
    @{
        Title = '4 · Andere Programme';
        Mode = 'Erst suchen, dann die Installation starten';
        Text = "Hier prüft der Assistent weitere unterstützte Programme, zum Beispiel Browser.`n`n1. Klicken Sie auf «1. Nach Updates suchen». Die Suche installiert noch nichts.`n2. Lesen Sie das Ergebnis. Unter «Details zum Vorgang» sehen Sie die Programmliste.`n3. Speichern Sie Ihre Arbeit und schließen Sie die betroffenen Programme.`n4. Klicken Sie auf «2. Programme aktualisieren», sobald die Suche Updates gefunden hat.`n`nDie zweite Schaltfläche bleibt bis dahin grau. Nicht jedes Programm kann automatisch aktualisiert werden.";
        Actions = @(@{
            Id = 'Scan';
            Label = '1. Nach Updates suchen'
        },@{
            Id = 'Install';
            Label = '2. Programme aktualisieren'
        });
        Manual = $false
    },
    @{
        Title = '5 · Aufräumen (optional)';
        Mode = 'Sie können diesen Schritt auslassen';
        Text = "Hier können Sie Programme entfernen, die Sie nicht mehr brauchen. Das ist für die Updates nicht erforderlich.`n`n1. Wenn Sie aufräumen möchten, klicken Sie auf «Installierte Apps öffnen».`n2. Suchen Sie ein bekanntes, nicht mehr benötigtes Programm.`n3. Öffnen Sie die drei Punkte daneben und wählen Sie «Deinstallieren».`n`nSie kennen ein Programm nicht? Lassen Sie es installiert.`n`nWenn Sie nichts entfernen möchten, gehen Sie einfach zum nächsten Schritt. Wenn Sie aufgeräumt haben, bestätigen Sie es unten.";
        Actions = @(@{
            Id = 'Apps';
            Label = 'Installierte Apps öffnen'
        },@{
            Id = 'ControlPanel';
            Label = 'Alternative Programmliste öffnen'
        });
        Manual = $true
    },
    @{
        Title = '6 · Virenschutz';
        Mode = 'Der Assistent aktualisiert den Windows-Virenschutz';
        Text = "Microsoft Defender ist der in Windows enthaltene Virenschutz. Neue Schutzinformationen helfen ihm, aktuelle Bedrohungen zu erkennen.`n`n1. Klicken Sie auf «Virenschutz aktualisieren».`n2. Warten Sie auf das Ergebnis unten.`n3. Öffnen Sie danach «Windows-Sicherheit öffnen» und beachten Sie dort angezeigte Hinweise.`n`nNutzen Sie einen anderen Virenschutz? Öffnen Sie stattdessen dessen Programm und aktualisieren Sie ihn dort. Der Assistent wechselt Ihren Virenschutz nicht.";
        Actions = @(@{
            Id = 'Defender';
            Label = 'Virenschutz aktualisieren'
        },@{
            Id = 'Security';
            Label = 'Windows-Sicherheit öffnen'
        });
        Manual = $false
    },
    @{
        Title = '7 · Lenovo-Gerät';
        Mode = 'Sie prüfen Geräteupdates im Lenovo-Programm';
        Text = "Dieser Schritt ist für Computer von Lenovo. Bei einem anderen Hersteller gehen Sie zum nächsten Schritt.`n`n1. Klicken Sie auf «Lenovo Vantage öffnen». Wenn Sie bereits System Update nutzen, öffnen Sie stattdessen dieses Programm.`n2. Fehlt das Programm? Installieren Sie eines der beiden Lenovo-Programme über die passende Schaltfläche. Eines genügt. Öffnen Sie es danach.`n3. Suchen Sie im Lenovo-Programm nach Geräteupdates und folgen Sie dessen Anweisungen.`n4. Kehren Sie nach Abschluss hierher zurück und bestätigen Sie Ihre Prüfung.`n`nBei einem BIOS- oder Firmware-Update wird die Grundsoftware des Computers aktualisiert. Lassen Sie das Ladekabel angeschlossen und schalten Sie den Computer nicht aus. Bei Fragen oder einer BitLocker-Schlüsselabfrage hilft IT Germany.";
        Actions = @(@{
            Id = 'Vantage';
            Label = 'Lenovo Vantage öffnen'
        },@{
            Id = 'SystemUpdate';
            Label = 'System Update öffnen'
        },@{
            Id = 'LenovoVantage';
            Label = 'Vantage installieren, falls es fehlt'
        },@{
            Id = 'LenovoSystemUpdate';
            Label = 'System Update installieren, falls es fehlt'
        },@{
            Id = 'LenovoSources';
            Label = 'Hilfe bei der Lenovo-Installation'
        });
        Manual = $true
    },
    @{
        Title = '8 · Zum Abschluss';
        Mode = 'Sie prüfen, ob noch etwas zu tun ist';
        Text = "1. Klicken Sie auf «Windows Update öffnen». Beachten Sie Hinweise auf weitere Updates oder einen nötigen Neustart.`n2. Falls ein Neustart verlangt wird: Speichern Sie Ihre Arbeit. Klicken Sie unten in Windows auf Start (das Windows-Zeichen), dann auf Ein/Aus und «Neu starten».`n3. Prüfen Sie nach dem Neustart Windows-Updates erneut. Öffnen Sie den Assistenten bei Bedarf wieder über die Startdatei.`n4. Bestätigen Sie unten Ihre Abschlussprüfung. Mit «Zusammenfassung ansehen» öffnen Sie die Ergebnisse dieser Sitzung.`n`nOffene oder fehlgeschlagene Schritte bedeuten, dass noch etwas zu prüfen ist. Die Zusammenfassung ist kein Nachweis, dass der Computer vollständig geschützt ist.";
        Actions = @(@{
            Id = 'WindowsUpdate';
            Label = 'Windows Update öffnen'
        },@{
            Id = 'History';
            Label = 'Bisherige Updates ansehen'
        },@{
            Id = 'Options';
            Label = 'Weitere Windows-Einstellungen'
        });
        Manual = $true
    }
)
# Language-specific step content. Keep the same step order and action IDs in both languages.
$script:StepsByLanguage = @{
    de = $script:Steps
    en = @(
        @{
            Title = '1 · Update Windows';
            Mode = 'The assistant searches and installs for you';
            Text = "Welcome. Work through the eight steps one after another. Nothing starts before you choose and confirm an action.`n`n1. Save your documents and close other programs.`n2. Connect the charger and make sure the computer is online.`n3. Click ""Start Windows updates"" and read the confirmation prompt.`n`nIf a restart is required, the computer restarts after 120 seconds. ""Postpone restart"" stops the countdown. Sign in again afterwards and check Windows here again.";
            Actions = @(@{
                Id = 'Windows';
                Label = 'Start Windows updates'
            },@{
                Id = 'WindowsUpdate';
                Label = 'Open Windows Update'
            });
            Manual = $false
        },
        @{
            Title = '2 · Devices and drivers';
            Mode = 'You review the offered updates in a Windows window';
            Text = "Drivers help Windows use devices such as the screen, printer, and speakers.`n`n1. Click ""Open optional updates"".`n2. Open ""Driver updates"" there if that entry is shown.`n3. Install only drivers you need. If you are unsure, ask IT Germany.`n4. Wait until installation has finished. Return here and tick the confirmation box below.`n`nNo drivers offered? You can confirm the check as well.";
            Actions = @(@{
                Id = 'Treiber';
                Label = 'Open optional updates'
            });
            Manual = $true
        },
        @{
            Title = '3 · Apps from the Store';
            Mode = 'You update apps in Microsoft Store';
            Text = "Microsoft Store is the Windows program for downloading and updating apps.`n`n1. Click ""Open Microsoft Store"".`n2. In Store, choose ""Downloads"" or ""Library"".`n3. Click ""Get updates"" or ""Update all"" if offered.`n4. Wait until the updates are complete. Return here and tick the confirmation box below.`n`nIf all apps are already current, this step is complete too.";
            Actions = @(@{
                Id = 'Store';
                Label = 'Open Microsoft Store'
            });
            Manual = $true
        },
        @{
            Title = '4 · Other programs';
            Mode = 'Search first, then start installation';
            Text = "Here the assistant checks other supported programs, for example browsers.`n`n1. Click ""1. Search for updates"". The search does not install anything yet.`n2. Read the result. Under ""Operation details"" you can see the program list.`n3. Save your work and close the affected programs.`n4. Click ""2. Update programs"" once the search has found updates.`n`nThe second button remains disabled until then. Not every program can be updated automatically.";
            Actions = @(@{
                Id = 'Scan';
                Label = '1. Search for updates'
            },@{
                Id = 'Install';
                Label = '2. Update programs'
            });
            Manual = $false
        },
        @{
            Title = '5 · Clean up (optional)';
            Mode = 'You can skip this step';
            Text = "Here you can remove programs that you no longer need. This is not required for the updates.`n`n1. If you want to clean up, click ""Open installed apps"".`n2. Find a known program that is no longer needed.`n3. Open the three dots beside it and choose ""Uninstall"".`n`nDo not know a program? Leave it installed.`n`nIf you do not want to remove anything, simply go to the next step. If you cleaned up, confirm it below.";
            Actions = @(@{
                Id = 'Apps';
                Label = 'Open installed apps'
            },@{
                Id = 'ControlPanel';
                Label = 'Open alternative program list'
            });
            Manual = $true
        },
        @{
            Title = '6 · Virus protection';
            Mode = 'The assistant updates Windows virus protection';
            Text = "Microsoft Defender is the virus protection included with Windows. New protection information helps it detect current threats.`n`n1. Click ""Update virus protection"".`n2. Wait for the result below.`n3. Then open ""Open Windows Security"" and follow any notices shown there.`n`nUsing another antivirus product? Open that program instead and update it there. The assistant does not switch your virus protection.";
            Actions = @(@{
                Id = 'Defender';
                Label = 'Update virus protection'
            },@{
                Id = 'Security';
                Label = 'Open Windows Security'
            });
            Manual = $false
        },
        @{
            Title = '7 · Lenovo device';
            Mode = 'You check device updates in the Lenovo program';
            Text = "This step is for Lenovo computers. For another manufacturer, go to the next step.`n`n1. Click ""Open Lenovo Vantage"". If you already use System Update, open that program instead.`n2. Program missing? Install one of the two Lenovo programs with the matching button. One is enough. Open it afterwards.`n3. Search for device updates in the Lenovo program and follow its instructions.`n4. Return here after completion and confirm your check.`n`nA BIOS or firmware update updates the computer's basic software. Keep the charger connected and do not switch off the computer. IT Germany can help with questions or a BitLocker key prompt.";
            Actions = @(@{
                Id = 'Vantage';
                Label = 'Open Lenovo Vantage'
            },@{
                Id = 'SystemUpdate';
                Label = 'Open System Update'
            },@{
                Id = 'LenovoVantage';
                Label = 'Install Vantage if missing'
            },@{
                Id = 'LenovoSystemUpdate';
                Label = 'Install System Update if missing'
            },@{
                Id = 'LenovoSources';
                Label = 'Help with Lenovo installation'
            });
            Manual = $true
        },
        @{
            Title = '8 · Finish';
            Mode = 'You check whether anything is still required';
            Text = "1. Click ""Open Windows Update"". Follow notices about more updates or a required restart.`n2. If a restart is requested: Save your work. Click Start in Windows, then Power, then ""Restart"".`n3. Check Windows updates again after the restart. Open the assistant again with the start file if needed.`n4. Confirm your final check below. ""View summary"" opens this session's results.`n`nOpen or failed steps mean that something still needs to be checked. The summary is not proof that the computer is fully protected.";
            Actions = @(@{
                Id = 'WindowsUpdate';
                Label = 'Open Windows Update'
            },@{
                Id = 'History';
                Label = 'View previous updates'
            },@{
                Id = 'Options';
                Label = 'More Windows settings'
            });
            Manual = $true
        }
    )
}
$script:Language = 'de'
# Shared display labels, hints and status translations.
$script:UiText = @{
    de = @{
        InstructionsHeader = 'Schritt-für-Schritt-Anleitung';
        AlternativesHeader = 'Weitere Möglichkeiten';
        SupportHeader = 'Hilfe & Dokumentation';
        StepIntro1 = 'Speichern Sie Ihre Arbeit und schließen Sie das Ladekabel an. Starten Sie dann die Windows-Updates. Falls nötig, folgt ein Neustart nach 120 Sekunden; Sie können ihn verschieben.';
        StepIntro2 = 'Öffnen Sie die optionalen Updates und prüfen Sie die angebotenen Treiber. Bestätigen Sie anschließend Ihre Prüfung hier.';
        StepIntro3 = 'Öffnen Sie den Microsoft Store und aktualisieren Sie Ihre Apps. Bestätigen Sie danach Ihre Prüfung hier.';
        StepIntro4 = 'Suchen Sie zuerst nach verfügbaren Programmupdates. Lesen Sie das Ergebnis, schließen Sie betroffene Programme und starten Sie dann die Installation.';
        StepIntro5 = 'Optional: Entfernen Sie Programme, die Sie nicht mehr benötigen. Unbekannte Programme bitte behalten. Sie können diesen Schritt offen lassen.';
        StepIntro6 = 'Aktualisieren Sie den Windows-Virenschutz. Prüfen Sie anschließend die Hinweise in Windows-Sicherheit unter „Weitere Möglichkeiten“.';
        StepIntro7 = 'Öffnen Sie Ihr Lenovo-Programm und prüfen Sie Geräteupdates. Bei Firmware-Updates: Ladekabel angeschlossen lassen und das Gerät nicht ausschalten. Bei anderen Herstellern weitergehen.';
        StepIntro8 = 'Prüfen Sie Windows Update ein letztes Mal und bestätigen Sie Ihre Abschlussprüfung. Die Zusammenfassung zeigt, was noch offen ist.';

        WindowTitle = 'WFW Update-Assistent';
        AppTitle = 'Update-Assistent';
        AppSubtitle = 'Schritt für Schritt durch die Updates – starten Sie links mit Schritt 1.';
        LanguageLabel = 'Sprache';
        LanguageAutomation = 'Sprache auswählen';
        ProgressLabel = 'Fortschritt';
        OverallProgressAutomation = 'Gesamtfortschritt';
        NavigationAutomation = 'Bereiche und Bearbeitungsstatus';
        CurrentStatusLabel = 'Aktueller Stand';
        NextActionLabel = 'Was mache ich als Nächstes?';
        ConfirmText = 'Ich habe die Prüfung im anderen Fenster abgeschlossen (auch wenn keine Updates angeboten wurden).';
        ConfirmAutomation = 'Prüfung manuell bestätigen';
        DetailsHeader = 'Details zum Vorgang';
        DetailAutomation = 'Technische Meldungen';
        HelpText = 'Anderes Fenster geöffnet? Kehren Sie über die Windows-Taskleiste zum Assistenten zurück. «Hilfe zur Bedienung» erklärt auch Fensterwechsel und Windows-Rückfragen.';
        Back = 'Zurück';
        Next = 'Weiter';
        Guide = 'Ausführliche Anleitung (PDF)';
        Help = 'Hilfe zur Bedienung';
        Report = 'Protokoll für IT';
        CancelRestart = 'Neustart verschieben';
        Footer = 'Ardawan Khosronezhad · IT Germany   |   Version 1.2 · Pilotfassung';
        DoneProgress = '{0} von 8 Bereichen bearbeitet';
        SectionCounter = 'SCHRITT {0} VON 8';
        Summary = 'Zusammenfassung ansehen';
        NextStep = 'Nächster Schritt →';
        ContinueOpen = 'Weiter (bleibt offen) →';
        HintCompleted = 'Dieser Schritt ist bearbeitet. Sie können zum nächsten Schritt gehen.';
        HintScanned = 'Lesen Sie die Programmliste unter «Details zum Vorgang». Starten Sie danach «2. Programme aktualisieren».';
        HintManual = 'Erledigen Sie die Prüfung im geöffneten Fenster. Kehren Sie hierher zurück und setzen Sie erst dann das Häkchen. Weitergehen allein bestätigt nichts.';
        HintAutomatic = 'Beginnen Sie mit der hervorgehobenen Schaltfläche oben. Lesen Sie danach das Ergebnis hier. Weitergehen allein bestätigt nichts.';
        HintSummary = ' Die Zusammenfassung zeigt auch Schritte, die noch offen sind.';
        Busy = 'Bitte warten und den Assistenten geöffnet lassen. Sie müssen nicht erneut klicken.';
        RunningMessage = 'Bitte warten. Der Vorgang kann mehrere Minuten dauern. Lassen Sie den Assistenten geöffnet.';
        NotStartedOrCancelled = 'Der Vorgang wurde nicht gestartet oder die Administratorabfrage wurde abgebrochen. Sie können erneut starten oder die manuelle Anleitung verwenden.';
        NotEdited = 'Noch nicht bearbeitet.';
        NotConfirmed = 'Noch nicht bestätigt.';
        ManualConfirmed = 'Von Ihnen als geprüft bestätigt. Der Assistent hat diesen Schritt nicht technisch überprüft.';
        Restore = 'Willkommen zurück. Bitte Windows erneut prüfen, damit nachgelagerte Updates ebenfalls installiert werden.';
        RestoreFailed = 'Bitte Windows-Updates erneut prüfen. Die frühere Sitzung konnte nicht übernommen werden.';
        RestartPostponed = 'Neustart verschoben. Speichern Sie Ihre Arbeit und starten Sie den Rechner später selbst neu. Danach Windows erneut prüfen.';
        Restart120 = 'Windows startet in 120 Sekunden neu. Speichern und schließen Sie Ihre Arbeit. Sie können den Neustart verschieben.';
        RestartCountdown = 'Automatischer Neustart in {0} Sekunden. Bitte Arbeit speichern. Mit «Neustart verschieben» stoppen Sie den Countdown.';
        RestartStarted = 'Neustart an Windows übergeben. Falls eine Anwendung ihn blockiert, speichern und schließen Sie diese. Danach gegebenenfalls über Start neu starten.';
        ResultMissing = 'Der Vorgang lieferte kein Ergebnis. Möglicherweise blockiert eine Richtlinie die Ausführung. Nutzen Sie die manuelle Anleitung; bei wiederholtem Fehler hilft IT Germany.';
        ResultReadFailed = 'Das Ergebnis konnte nicht gelesen werden. Prüfen Sie den Zustand über die manuelle Anleitung.';
        StillRunning = 'Der Vorgang läuft noch. Die Meldungen können vorübergehend nicht gelesen werden.';
        OpenTargetFailed = 'Das Fenster konnte nicht geöffnet werden. Nutzen Sie den entsprechenden Abschnitt in der Anleitung.';
        OpenManualTitle = 'Bitte manuell öffnen';
        AlreadyOpen = 'Der Update-Assistent ist bereits geöffnet. Wechseln Sie zum vorhandenen Fenster.';
        AlreadyOpenTitle = 'Bereits geöffnet';
        StartFailedTitle = 'Update-Assistent';
        StartFailedIntro = 'Der Assistent konnte nicht gestartet werden.';
        ManualGuide = 'Nutzen Sie die manuelle Anleitung.';
        BusyClose = 'Ein Update-Vorgang läuft noch. Bitte warten Sie, bis er beendet ist. Sie können dieses Fenster währenddessen minimieren.';
        BusyCloseTitle = 'Vorgang läuft';
        ReportOpenFailed = 'Das Protokoll konnte nicht geöffnet werden.';
        ReportTitle = 'Protokoll';
        GuideOpenFailed = 'Die PDF konnte nicht geöffnet werden. Öffnen Sie Anleitung.pdf im entpackten Ordner.';
        GuideMissing = 'Öffnen Sie die separat mitgelieferte PDF-Anleitung.';
        GuideTitle = 'Anleitung';
        HelpDialog = "So verwenden Sie den Assistenten:`n`n• Beginnen Sie oben mit der farbigen Schaltfläche. Lesen Sie danach den aktuellen Stand.`n• Öffnet sich ein anderes Fenster, erledigen Sie dort die beschriebenen Schritte.`n• Zurück zum Assistenten: Klicken Sie auf sein Symbol unten in der Windows-Taskleiste. Oder halten Sie Alt gedrückt und drücken Sie Tab, bis der Assistent ausgewählt ist.`n• Eine graue Schaltfläche ist gerade nicht verfügbar. Warten Sie auf den laufenden Vorgang oder führen Sie zuerst die Suche aus.`n• Fragt Windows, ob Änderungen erlaubt sind? Prüfen Sie, ob die Abfrage zu Ihrer gerade gestarteten Aktion gehört. Wenn Ihnen die nötigen Rechte fehlen oder Sie unsicher sind, wählen Sie Nein und fragen Sie IT Germany.`n• Weitergehen markiert einen Schritt nicht als erledigt. Offene Schritte sehen Sie links.`n`nBei Problemen: Notieren Sie die Meldung. Über «Protokoll für IT» können Sie die Ergebnisdateien öffnen; es wird nichts automatisch versendet.";
        HelpTitle = 'Hilfe zur Bedienung';
        StateOpen = 'Offen';
        StateRunning = 'Läuft';
        StateUserConfirmed = 'Benutzer bestätigt';
        StateAuto = 'Automatisch bearbeitet';
        StateCheck = 'Bitte prüfen';
        StateRestart = 'Neustart nötig';
        StateScanned = 'Suche abgeschlossen';
        StateToolReady = 'Programm bereit'
    }
    en = @{
        InstructionsHeader = 'Step-by-step instructions';
        AlternativesHeader = 'More options';
        SupportHeader = 'Help & documentation';
        StepIntro1 = 'Save your work and connect the charger, then start Windows updates. If needed, a restart follows after 120 seconds; you can postpone it.';
        StepIntro2 = 'Open optional updates and review the available drivers. Return here to confirm your check.';
        StepIntro3 = 'Open Microsoft Store and update your apps. Return here to confirm your check.';
        StepIntro4 = 'Search for program updates first. Review the result, close affected programs, then start installation.';
        StepIntro5 = 'Optional: Remove programs you no longer need. Keep unfamiliar programs installed. You can leave this step open.';
        StepIntro6 = 'Update Windows virus protection. Then review Windows Security using the button under “More options”.';
        StepIntro7 = 'Open your Lenovo program and check device updates. During firmware updates, keep the charger connected and do not turn off the device. For other manufacturers, continue.';
        StepIntro8 = 'Check Windows Update once more and confirm your final check. The summary shows anything still open.';

        WindowTitle = 'WFW Update Assistant';
        AppTitle = 'Update Assistant';
        AppSubtitle = 'Step by step through the updates - start on the left with step 1.';
        LanguageLabel = 'Language';
        LanguageAutomation = 'Choose language';
        ProgressLabel = 'Progress';
        OverallProgressAutomation = 'Overall progress';
        NavigationAutomation = 'Sections and processing status';
        CurrentStatusLabel = 'Current status';
        NextActionLabel = 'What should I do next?';
        ConfirmText = 'I have completed the check in the other window (even if no updates were offered).';
        ConfirmAutomation = 'Confirm manual check';
        DetailsHeader = 'Operation details';
        DetailAutomation = 'Technical messages';
        HelpText = 'Other window open? Return to the assistant through the Windows taskbar. "Usage help" also explains window switching and Windows prompts.';
        Back = 'Back';
        Next = 'Next';
        Guide = 'Detailed guide (PDF)';
        Help = 'Usage help';
        Report = 'Log for IT';
        CancelRestart = 'Postpone restart';
        Footer = 'Ardawan Khosronezhad · IT Germany   |   Version 1.2 · pilot version';
        DoneProgress = '{0} of 8 sections completed';
        SectionCounter = 'STEP {0} OF 8';
        Summary = 'View summary';
        NextStep = 'Next step →';
        ContinueOpen = 'Continue (keeps open) →';
        HintCompleted = 'This step is complete. You can go to the next step.';
        HintScanned = 'Read the program list under "Operation details". Then start "2. Update programs".';
        HintManual = 'Complete the check in the opened window. Return here and only then tick the box. Continuing alone does not confirm anything.';
        HintAutomatic = 'Start with the highlighted button above. Then read the result here. Continuing alone does not confirm anything.';
        HintSummary = ' The summary also shows steps that are still open.';
        Busy = 'Please wait and keep the assistant open. You do not need to click again.';
        RunningMessage = 'Please wait. The operation can take several minutes. Leave the assistant open.';
        NotStartedOrCancelled = 'The operation was not started or the administrator prompt was cancelled. You can start again or use the manual guide.';
        NotEdited = 'Not started yet.';
        NotConfirmed = 'Not confirmed yet.';
        ManualConfirmed = 'Confirmed by you as checked. The assistant did not technically verify this step.';
        Restore = 'Welcome back. Please check Windows again so later updates are installed too.';
        RestoreFailed = 'Please check Windows updates again. The earlier session could not be restored.';
        RestartPostponed = 'Restart postponed. Save your work and restart the computer yourself later. Then check Windows again.';
        Restart120 = 'Windows restarts in 120 seconds. Save and close your work. You can postpone the restart.';
        RestartCountdown = 'Automatic restart in {0} seconds. Please save your work. Use "Postpone restart" to stop the countdown.';
        RestartStarted = 'Restart handed over to Windows. If an app blocks it, save and close that app. Restart from Start if needed afterwards.';
        ResultMissing = 'The operation returned no result. A policy might be blocking execution. Use the manual guide; IT Germany can help if this repeats.';
        ResultReadFailed = 'The result could not be read. Check the state using the manual guide.';
        StillRunning = 'The operation is still running. Messages may temporarily be unreadable.';
        OpenTargetFailed = 'The window could not be opened. Use the matching section in the guide.';
        OpenManualTitle = 'Open manually';
        AlreadyOpen = 'The update assistant is already open. Switch to the existing window.';
        AlreadyOpenTitle = 'Already open';
        StartFailedTitle = 'Update Assistant';
        StartFailedIntro = 'The assistant could not be started.';
        ManualGuide = 'Use the manual guide.';
        BusyClose = 'An update operation is still running. Please wait until it has finished. You can minimize this window meanwhile.';
        BusyCloseTitle = 'Operation running';
        ReportOpenFailed = 'The log could not be opened.';
        ReportTitle = 'Log';
        GuideOpenFailed = 'The PDF could not be opened. Open Anleitung.pdf in the extracted folder.';
        GuideMissing = 'Open the separately supplied PDF guide.';
        GuideTitle = 'Guide';
        HelpDialog = "How to use the assistant:`n`n• Start with the colored button at the top. Then read the current status.`n• If another window opens, complete the steps described there.`n• Return to the assistant by clicking its icon in the Windows taskbar. Or hold Alt and press Tab until the assistant is selected.`n• A grey button is currently unavailable. Wait for the running operation or run the search first.`n• Does Windows ask whether changes are allowed? Check whether the prompt belongs to the action you just started. If you lack the required rights or are unsure, choose No and ask IT Germany.`n• Continuing does not mark a step as complete. Open steps are shown on the left.`n`nIf there are problems: Note the message. With ""Log for IT"" you can open the result files; nothing is sent automatically.";
        HelpTitle = 'Usage help';
        StateOpen = 'Open';
        StateRunning = 'Running';
        StateUserConfirmed = 'Confirmed by user';
        StateAuto = 'Automatically processed';
        StateCheck = 'Please check';
        StateRestart = 'Restart required';
        StateScanned = 'Search completed';
        StateToolReady = 'Program ready'
    }
}
# Session state: parallel arrays use the same index as the step definitions.
$script:Steps = $script:StepsByLanguage[$script:Language]
$script:States = @($script:Steps | ForEach-Object {
    'Offen'
})
$script:Messages = @($script:Steps | ForEach-Object {
    'Noch nicht bearbeitet.'
})
$script:DetailLogs = @($script:Steps | ForEach-Object {
    ''
})
$script:Index = 0
$script:Busy = $false
$script:ActiveProcess = $null
$script:CurrentRun = $null
$script:ActiveTask = ''
$script:HasScan = $false
$script:NavStatus = @()
$script:Events = New-Object 'System.Collections.Generic.List[string]'

# Resolve a label in the selected language, falling back to German.
function Get-UiText([string]$Key) {
    $text = $script:UiText[$script:Language][$Key]
    if ($null -eq $text) {
        $text = $script:UiText.de[$Key]
    }
    [string]$text
}

# Translate internal state names without changing the stored state values.
function Get-StateText([string]$State) {
    switch ($State) {
        'Offen' {
            Get-UiText 'StateOpen'
        }
        'Läuft' {
            Get-UiText 'StateRunning'
        }
        'Benutzer bestätigt' {
            Get-UiText 'StateUserConfirmed'
        }
        'Automatisch bearbeitet' {
            Get-UiText 'StateAuto'
        }
        'Bitte prüfen' {
            Get-UiText 'StateCheck'
        }
        'Neustart nötig' {
            Get-UiText 'StateRestart'
        }
        'Suche abgeschlossen' {
            Get-UiText 'StateScanned'
        }
        'Programm bereit' {
            Get-UiText 'StateToolReady'
        }
        default {
            $State
        }
    }
}

# Map each processing state to its Segoe status glyph.
function Get-StateIcon([string]$State) {
    switch ($State) {
        'Läuft' {
            [char]0xE9F5
        }
        'Benutzer bestätigt' {
            [char]0xE73E
        }
        'Automatisch bearbeitet' {
            [char]0xE73E
        }
        'Bitte prüfen' {
            [char]0xE7BA
        }
        'Neustart nötig' {
            [char]0xE777
        }
        'Suche abgeschlossen' {
            [char]0xE721
        }
        'Programm bereit' {
            [char]0xE930
        }
        default {
            [char]0xE10F
        }
    }
}

# Update a named control only when it exists in the loaded layout.
function Set-ControlText([string]$Name, [string]$Property, [string]$Text) {
    if ($script:Ui[$Name]) {
        $script:Ui[$Name].$Property = $Text
    }
}

# Refresh window labels and accessibility names after a language change.
function Apply-StaticText {
    Set-ControlText 'Instructions' 'Header' (Get-UiText 'InstructionsHeader')
    Set-ControlText 'Alternatives' 'Header' (Get-UiText 'AlternativesHeader')
    Set-ControlText 'Support' 'Header' (Get-UiText 'SupportHeader')
    $script:Window.Title = Get-UiText 'WindowTitle'
    Set-ControlText 'AppTitle' 'Text' (Get-UiText 'AppTitle')
    Set-ControlText 'AppSubtitle' 'Text' (Get-UiText 'AppSubtitle')
    Set-ControlText 'LanguageLabel' 'Text' (Get-UiText 'LanguageLabel')
    Set-ControlText 'ProgressLabel' 'Text' (Get-UiText 'ProgressLabel')
    Set-ControlText 'CurrentStatusLabel' 'Text' (Get-UiText 'CurrentStatusLabel')
    Set-ControlText 'NextActionLabel' 'Text' (Get-UiText 'NextActionLabel')
    Set-ControlText 'ConfirmText' 'Text' (Get-UiText 'ConfirmText')
    Set-ControlText 'HelpText' 'Text' (Get-UiText 'HelpText')
    Set-ControlText 'Back' 'Content' (Get-UiText 'Back')
    Set-ControlText 'Guide' 'Content' (Get-UiText 'Guide')
    Set-ControlText 'Help' 'Content' (Get-UiText 'Help')
    Set-ControlText 'Report' 'Content' (Get-UiText 'Report')
    Set-ControlText 'CancelRestart' 'Content' (Get-UiText 'CancelRestart')
    Set-ControlText 'FooterText' 'Text' (Get-UiText 'Footer')
    if ($script:Ui.Details) {
        $script:Ui.Details.Header = Get-UiText 'DetailsHeader'
    }
    if ($script:Ui.LanguageSwitch) {
        [Windows.Automation.AutomationProperties]::SetName($script:Ui.LanguageSwitch, (Get-UiText 'LanguageAutomation'))
    }
    if ($script:Ui.Navigation) {
        [Windows.Automation.AutomationProperties]::SetName($script:Ui.Navigation, (Get-UiText 'NavigationAutomation'))
    }
    if ($script:Ui.OverallProgress) {
        [Windows.Automation.AutomationProperties]::SetName($script:Ui.OverallProgress, (Get-UiText 'OverallProgressAutomation'))
    }
    if ($script:Ui.Confirm) {
        [Windows.Automation.AutomationProperties]::SetName($script:Ui.Confirm, (Get-UiText 'ConfirmAutomation'))
    }
    if ($script:Ui.DetailText) {
        [Windows.Automation.AutomationProperties]::SetName($script:Ui.DetailText, (Get-UiText 'DetailAutomation'))
    }
    if ($script:Ui.CancelRestart) {
        [Windows.Automation.AutomationProperties]::SetName($script:Ui.CancelRestart, (Get-UiText 'CancelRestart'))
    }
}

# Refresh the icon beside the current step status.
function Set-StatusVisual([string]$State) {
    if ($script:Ui.StatusIcon) {
        $script:Ui.StatusIcon.Text = [string](Get-StateIcon $State)
        $brush = switch ($State) {
            'Läuft' { 'RunningBrush' }
            'Benutzer bestätigt' { 'SuccessBrush' }
            'Automatisch bearbeitet' { 'SuccessBrush' }
            'Bitte prüfen' { 'WarningBrush' }
            'Neustart nötig' { 'WarningBrush' }
            default { 'BrandBrush' }
        }
        $script:Ui.StatusIcon.Foreground = $script:Window.FindResource($brush)
    }
}

# Switch display text while retaining step results and worker messages.
function Set-Language([string]$Language) {
    if ($Language -notin @('de','en')) {
        return
    }
    $script:Language = $Language
    $script:Steps = $script:StepsByLanguage[$script:Language]
    for ($i = 0; $i -lt $script:Messages.Count; $i++) {
        if ($script:States[$i] -eq 'Offen' -and $script:Messages[$i] -in @($script:UiText.de.NotEdited,$script:UiText.en.NotEdited)) {
            $script:Messages[$i] = Get-UiText 'NotEdited'
        }
        elseif ($script:States[$i] -eq 'Offen' -and $script:Messages[$i] -in @($script:UiText.de.NotConfirmed,$script:UiText.en.NotConfirmed)) {
            $script:Messages[$i] = Get-UiText 'NotConfirmed'
        }
        elseif ($script:States[$i] -eq 'Benutzer bestätigt' -and $script:Messages[$i] -in @($script:UiText.de.ManualConfirmed,$script:UiText.en.ManualConfirmed)) {
            $script:Messages[$i] = Get-UiText 'ManualConfirmed'
        }
        elseif ($script:States[$i] -eq 'Läuft' -and $script:Messages[$i] -in @($script:UiText.de.RunningMessage,$script:UiText.en.RunningMessage)) {
            $script:Messages[$i] = Get-UiText 'RunningMessage'
        }
    }
    Apply-StaticText
    for ($i = 0; $i -lt $script:Ui.Navigation.Items.Count; $i++) {
        $item = $script:Ui.Navigation.Items[$i]
        if ($item -and $item.Tag -and $item.Tag.Title) {
            $item.Tag.Title.Text = $script:Steps[$i].Title -replace '^\d+ · ', ''
        }
    }
    Show-Step
}

# Return the localized guidance for opening an external Windows tool.
function Get-ActionMessage([string]$Key) {
    $messages = @{
        de = @{
            Treiber = 'Fenster angefordert. Treiber bitte dort auswählen und installieren; danach hier bestätigen.'
            Store = 'Store angefordert. Unter Downloads oder Bibliothek Updates abrufen und abschließen; danach hier bestätigen.'
            Apps = 'Installierte Apps angefordert. Nur bekannte, nicht mehr benötigte Programme selbst entfernen.'
            ControlPanel = 'Programme und Features angefordert. Gewünschte Programme selbst auswählen.'
            Security = 'Windows-Sicherheit angefordert. Öffnen Sie Windows-Sicherheit und prüfen Sie die angezeigten Hinweise.'
            VantageStore = 'Vantage-Storeseite angefordert. Dort Installieren wählen; anschließend hier Vantage öffnen.'
            LenovoDownload = 'Lenovo-Downloadseite angefordert. Kompatibilität prüfen, Installer herunterladen und ausführen; danach hier System Update öffnen.'
            WindowsUpdate = 'Windows Update angefordert. Suchen Sie nach Updates und beachten Sie ausstehende Neustarts.'
            History = 'Updateverlauf angefordert. Prüfen Sie, ob Updates fehlgeschlagen sind.'
            Options = 'Erweiterte Optionen angefordert. Prüfen Sie dort Ihre gewünschten Einstellungen.'
            LenovoOpened = 'Lenovo-Programm zum Öffnen angefordert. Suchen und installieren Sie dort die passenden Updates. Anschließend hier bestätigen.'
        }
        en = @{
            Treiber = 'Window requested. Select and install drivers there, then confirm here.'
            Store = 'Store requested. Get updates under Downloads or Library and finish them, then confirm here.'
            Apps = 'Installed apps requested. Remove only known programs you no longer need.'
            ControlPanel = 'Programs and Features requested. Select the desired programs yourself.'
            Security = 'Windows Security requested. Open Windows Security and check the notices shown there.'
            VantageStore = 'Vantage Store page requested. Choose Install there, then open Vantage here.'
            LenovoDownload = 'Lenovo download page requested. Check compatibility, download and run the installer, then open System Update here.'
            WindowsUpdate = 'Windows Update requested. Search for updates and watch for pending restarts.'
            History = 'Update history requested. Check whether updates failed.'
            Options = 'Advanced options requested. Check your preferred settings there.'
            LenovoOpened = 'Lenovo program requested. Search for and install the matching updates there. Confirm here afterwards.'
        }
    }
    [string]$messages[$script:Language][$Key]
}

# Build the confirmation shown before a worker action starts.
function Get-StartDialog([string]$Task, [string]$ToolName) {
    $dialogs = @{
        de = @{
            LenovoTitle = 'Lenovo-Tool installieren'
            LenovoMessage = ($ToolName + ' wird nur installiert, wenn es noch fehlt. Die Paket- und Quellbedingungen werden akzeptiert. Bei Microsoft Store wird die Geräteregion an den Dienst übermittelt. Administratorrechte oder Store-Anmeldung können erforderlich sein. Es genügt eines der beiden Tools. Fortfahren?')
            WindowsTitle = 'Windows aktualisieren und bei Bedarf neu starten'
            WindowsMessage = "Haben Sie Ihre Arbeit gespeichert und andere Programme geschlossen?`n`nNach «Ja» sucht und installiert der Assistent passende Windows-Updates. Auf nicht zentral verwalteten Geräten passt er bei Bedarf lokale Update-Einstellungen an. Dabei werden die Lizenzbedingungen der Updates akzeptiert.`n`nFalls nötig, startet der Computer nach einem Countdown von 120 Sekunden neu. Mit «Neustart verschieben» können Sie den Countdown stoppen.`n`nJetzt starten?"
            ScanTitle = 'Nach Programmupdates suchen'
            ScanMessage = 'Die Suche verwendet Microsofts öffentliche winget-Quelle und akzeptiert deren Quellbedingungen. Es werden noch keine Programme installiert. Fortfahren?'
            InstallTitle = 'Programmupdates starten'
            InstallMessage = 'Alle von winget unterstützten, aktualisierbaren Programme werden aktualisiert. Dabei werden die Paket-Lizenzbedingungen automatisch akzeptiert. Fahren Sie nur fort, wenn Sie dazu berechtigt sind. Speichern und schließen Sie vorher alle offenen Programme. Installation starten?'
            DefenderTitle = 'Defender aktualisieren'
            DefenderMessage = 'Die Schutzinformationen des Windows-Virenschutzes werden aktualisiert. Windows kann fragen, ob Änderungen am Computer erlaubt sind. Wenn Ihnen die nötigen Rechte fehlen, wählen Sie Nein und wenden Sie sich an IT Germany. Jetzt starten?'
        }
        en = @{
            LenovoTitle = 'Install Lenovo tool'
            LenovoMessage = ($ToolName + ' is installed only if it is missing. Package and source terms are accepted. With Microsoft Store, the device region is sent to the service. Administrator rights or Store sign-in may be required. One of the two tools is enough. Continue?')
            WindowsTitle = 'Update Windows and restart if needed'
            WindowsMessage = "Have you saved your work and closed other programs?`n`nAfter ""Yes"", the assistant searches for and installs matching Windows updates. On devices that are not centrally managed, it adjusts local update settings if required. The update license terms are accepted.`n`nIf needed, the computer restarts after a 120-second countdown. ""Postpone restart"" stops the countdown.`n`nStart now?"
            ScanTitle = 'Search for program updates'
            ScanMessage = 'The search uses Microsoft''s public winget source and accepts its source terms. No programs are installed yet. Continue?'
            InstallTitle = 'Start program updates'
            InstallMessage = 'All updateable programs supported by winget are updated. Package license terms are accepted automatically. Continue only if you are authorized to do this. Save and close all open programs first. Start installation?'
            DefenderTitle = 'Update Defender'
            DefenderMessage = 'The protection information for Windows virus protection is updated. Windows may ask whether changes to the computer are allowed. If you lack the required rights, choose No and contact IT Germany. Start now?'
        }
    }
    if ($Task -in @('LenovoVantage','LenovoSystemUpdate')) {
        return @{
            Title = $dialogs[$script:Language].LenovoTitle;
            Message = $dialogs[$script:Language].LenovoMessage
        }
    }
    if ($Task -eq 'Windows') {
        return @{
            Title = $dialogs[$script:Language].WindowsTitle;
            Message = $dialogs[$script:Language].WindowsMessage
        }
    }
    if ($Task -eq 'Scan') {
        return @{
            Title = $dialogs[$script:Language].ScanTitle;
            Message = $dialogs[$script:Language].ScanMessage
        }
    }
    if ($Task -eq 'Install') {
        return @{
            Title = $dialogs[$script:Language].InstallTitle;
            Message = $dialogs[$script:Language].InstallMessage
        }
    }
    @{
        Title = $dialogs[$script:Language].DefenderTitle;
        Message = $dialogs[$script:Language].DefenderMessage
    }
}

# Append a timestamped entry to the in-memory session history.
function Add-Event([string]$Message) {
    $script:Events.Add(('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Message))
}

# Write step results and session events to the local IT summary.
function Save-Report {
    $lines = @('WFW Update-Assistent 1.2', 'Ardawan Khosronezhad | IT Germany', ('Stand: ' + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')), '', 'Diese Angaben gelten nur für diese Sitzung. Manuelle Bestätigungen wurden nicht technisch geprüft.', '')
    for ($i = 0; $i -lt $script:Steps.Count; $i++) {
        $lines += ($script:Steps[$i].Title + ': ' + $script:States[$i]);
        $lines += $script:Messages[$i];
        $lines += ''
    }
    $lines += 'Ablauf:';
    $lines += $script:Events.ToArray()
    $lines | Set-Content -LiteralPath (Join-Path $script:SessionDirectory 'Zusammenfassung.txt') -Encoding UTF8
}

# Count completed steps and synchronize navigation status indicators.
function Refresh-Progress {
    $done = @($script:States | Where-Object {
        $_ -eq 'Benutzer bestätigt' -or $_ -eq 'Automatisch bearbeitet'
    }).Count
    for ($i = 0; $i -lt $script:NavStatus.Count; $i++) {
        # Keep step numbers stable; the adjacent caption describes the processing state.
        $script:NavStatus[$i].Icon.Text = [string]($i + 1)
        $script:NavStatus[$i].Caption.Text = Get-StateText $script:States[$i]
    }
    $script:Ui.OverallProgress.Value = $done
    $script:Ui.ProgressText.Text = (Get-UiText 'DoneProgress') -f $done
}

# Build scalable outline-icon content. Bind both parts to the owning button foreground.
function New-IconButtonContent($Button, [string]$Text, [string]$IconKey) {
    $grid = New-Object Windows.Controls.Grid
    $iconColumn = New-Object Windows.Controls.ColumnDefinition
    $iconColumn.Width = New-Object Windows.GridLength -ArgumentList 28
    $textColumn = New-Object Windows.Controls.ColumnDefinition
    $textColumn.Width = New-Object Windows.GridLength -ArgumentList 1,([Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($iconColumn)
    $grid.ColumnDefinitions.Add($textColumn)
    $icon = New-Object Windows.Shapes.Path
    $icon.Data = $script:Window.FindResource($IconKey)
    $icon.Width = 18
    $icon.Height = 18
    $icon.Stretch = 'Uniform'
    $icon.StrokeThickness = 1.8
    $icon.StrokeStartLineCap = 'Round'
    $icon.StrokeEndLineCap = 'Round'
    $icon.StrokeLineJoin = 'Round'
    $icon.VerticalAlignment = 'Center'
    $icon.HorizontalAlignment = 'Left'
    $icon.IsHitTestVisible = $false
    $stroke = New-Object Windows.Data.Binding -ArgumentList 'Foreground'
    $stroke.Source = $Button
    $icon.SetBinding([Windows.Shapes.Shape]::StrokeProperty, $stroke) | Out-Null
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.TextWrapping = 'Wrap'
    $label.VerticalAlignment = 'Center'
    $foreground = New-Object Windows.Data.Binding -ArgumentList 'Foreground'
    $foreground.Source = $Button
    $label.SetBinding([Windows.Controls.TextBlock]::ForegroundProperty, $foreground) | Out-Null
    [Windows.Controls.Grid]::SetColumn($label, 1)
    $grid.Children.Add($icon) | Out-Null
    $grid.Children.Add($label) | Out-Null
    return $grid
}

# Stable action IDs select a visual symbol; action routing is unchanged.
function Get-ActionIconKey([string]$Action) {
    switch ($Action) {
        'Windows' { 'IconRefresh' }
        'Scan' { 'IconSearch' }
        'Install' { 'IconDownload' }
        'Defender' { 'IconShield' }
        'Security' { 'IconShield' }
        'Store' { 'IconApps' }
        'Apps' { 'IconApps' }
        'LenovoVantage' { 'IconDownload' }
        'LenovoSystemUpdate' { 'IconDownload' }
        'Vantage' { 'IconDevice' }
        'SystemUpdate' { 'IconDevice' }
        default { 'IconExternal' }
    }
}

# Render the selected step, its available actions, result and next-step guidance.
function Show-Step {
    $step = $script:Steps[$script:Index]
    # Reset disclosures only when moving to another step, not on status refresh.
    if ($script:RenderedStep -ne $script:Index) {
        $script:Ui.Instructions.IsExpanded = $false
        $script:Ui.Alternatives.IsExpanded = $false
        $script:Ui.Details.IsExpanded = $false
        $script:RenderedStep = $script:Index
    }
    $script:Ui.StepIntro.Text = Get-UiText ('StepIntro' + ($script:Index + 1))
    $script:Ui.StepTitle.Text = $step.Title -replace '^\d+ · ', ''
    $script:Ui.StepMode.Text = $step.Mode
    $script:Ui.StepText.Text = $step.Text
    $script:Ui.Status.Text = $script:Messages[$script:Index]
    Set-StatusVisual $script:States[$script:Index]
    $script:Ui.DetailText.Text = $script:DetailLogs[$script:Index]
    $script:Ui.Confirm.Visibility = if ($step.Manual) {
        'Visible'
    } else {
        'Collapsed'
    }
    $script:Ui.Confirm.IsChecked = ($script:States[$script:Index] -eq 'Benutzer bestätigt')
    $script:Ui.Actions.Children.Clear()
    $script:Ui.AdditionalActions.Children.Clear()
    $primaryAction = if ($script:Index -eq 3 -and $script:HasScan) {
        'Install'
    } else {
        $step.Actions[0].Id
    }
    foreach ($action in $step.Actions) {
        $button = New-Object Windows.Controls.Button
        $button.Content = New-IconButtonContent $button $action.Label (Get-ActionIconKey $action.Id)
        $button.Tag = $action.Id
        $button.MaxWidth = 280
        [Windows.Automation.AutomationProperties]::SetName($button, $action.Label)
        $button.Style = if ($action.Id -eq $primaryAction) {
            $script:Window.FindResource('PrimaryButton')
        } else {
            $script:Window.FindResource('SecondaryButton')
        }
        if ($action.Id -eq 'Install') {
            $button.IsEnabled = $script:HasScan
        }
        $button.Add_Click({
            param($sender,$eventArgs) Invoke-StepAction ([string]$sender.Tag)
        })
        # Keep the search/install sequence visible; other alternatives are secondary.
        if ($action.Id -eq $primaryAction -or $script:Index -eq 3) {
            $script:Ui.Actions.Children.Add($button) | Out-Null
        } else {
            $script:Ui.AdditionalActions.Children.Add($button) | Out-Null
        }
    }
    $script:Ui.Alternatives.Visibility = if ($script:Ui.AdditionalActions.Children.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $script:Ui.Back.IsEnabled = ($script:Index -gt 0)
    $completed = $script:States[$script:Index] -in @('Benutzer bestätigt','Automatisch bearbeitet')
    $nextStyle = if ($completed -or $script:Index -eq 7) { 'PrimaryButton' } else { 'SecondaryButton' }
    $script:Ui.Next.Style = $script:Window.FindResource($nextStyle)
    $script:Ui.Next.Content = if ($script:Index -eq 7) {
        Get-UiText 'Summary'
    } elseif ($completed) {
        Get-UiText 'NextStep'
    } else {
        Get-UiText 'ContinueOpen'
    }
    $script:Ui.NextHint.Text = if ($completed) {
        Get-UiText 'HintCompleted'
    } elseif ($script:States[$script:Index] -eq 'Suche abgeschlossen') {
        Get-UiText 'HintScanned'
    } elseif ($step.Manual) {
        Get-UiText 'HintManual'
    } else {
        Get-UiText 'HintAutomatic'
    }
    if ($script:Index -eq 7) {
        $script:Ui.NextHint.Text += Get-UiText 'HintSummary'
    }
    $script:Ui.SectionCounter.Text = (Get-UiText 'SectionCounter') -f ($script:Index + 1)
    $script:Ui.Back.Content = New-IconButtonContent $script:Ui.Back (Get-UiText 'Back') 'IconArrowLeft'
    $nextText = [string]$script:Ui.Next.Content
    $script:Ui.Next.Content = New-IconButtonContent $script:Ui.Next $nextText 'IconArrowRight'
    [Windows.Automation.AutomationProperties]::SetName($script:Ui.Next, $nextText)
    [Windows.Automation.AutomationProperties]::SetName($script:Ui.Back, (Get-UiText 'Back'))
    foreach ($key in @('Guide','Help','Report')) {
        $iconKey = if ($key -eq 'Help') { 'IconHelp' } else { 'IconDocument' }
        $script:Ui[$key].Content = New-IconButtonContent $script:Ui[$key] (Get-UiText $key) $iconKey
        [Windows.Automation.AutomationProperties]::SetName($script:Ui[$key], (Get-UiText $key))
    }
    Refresh-Progress
}

# Open a Windows settings URI or program and record the handoff to the user.
function Open-Target([string]$Target, [string]$Text) {
    try {
        Start-Process -FilePath $Target -ErrorAction Stop | Out-Null
        $script:Messages[$script:Index] = $Text
        Add-Event $Text
        Show-Step
    } catch {
        [Windows.MessageBox]::Show(((Get-UiText 'OpenTargetFailed') + "`n`n$($_.Exception.Message)"), (Get-UiText 'OpenManualTitle')) | Out-Null
    }
}

# Lock navigation during background work and restore the step view afterward.
function Set-Busy([bool]$Value) {
    $script:Busy = $Value
    foreach ($key in @('Navigation','Actions','AdditionalActions','Back','Next','Confirm')) {
        $script:Ui[$key].IsEnabled = -not $Value
    }
    $script:Ui.BusyBar.Visibility = if ($Value) {
        'Visible'
    } else {
        'Collapsed'
    }
    if ($Value) {
        $script:Ui.NextHint.Text = Get-UiText 'Busy'
    }
    if (-not $Value) {
        Show-Step
    }
}

# Confirm the action, launch an isolated worker and start polling its result files.
function Start-Task([string]$Task) {
    if ($script:Busy) {
        return
    }
    if ($Task -in @('LenovoVantage','LenovoSystemUpdate')) {
        $name = if ($Task -eq 'LenovoVantage') {
            'Lenovo Vantage'
        } else {
            'Lenovo System Update'
        }
        $dialog = Get-StartDialog $Task $name
    } elseif ($Task -eq 'Windows') {
        $dialog = Get-StartDialog $Task ''
    } elseif ($Task -eq 'Scan') {
        $dialog = Get-StartDialog $Task ''
    } elseif ($Task -eq 'Install') {
        $dialog = Get-StartDialog $Task ''
    } else {
        $dialog = Get-StartDialog $Task ''
    }
    $choice = [Windows.MessageBox]::Show($dialog.Message, $dialog.Title, 'YesNo', 'Question')
    if ($choice -ne 'Yes') {
        return
    }
    try {
        $script:CurrentRun = Join-Path $script:SessionDirectory ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:CurrentRun | Out-Null
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Vollständige Pfade in doppelten Anführungszeichen; keine dynamischen Befehle.
        $argumentLine = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "{0}" -Mode {1} -RunDirectory "{2}"' -f $script:ScriptPath,$Task,$script:CurrentRun
        $parameters = @{
            FilePath = $exe;
            ArgumentList = $argumentLine;
            PassThru = $true;
            WindowStyle = 'Hidden';
            ErrorAction = 'Stop'
        }
        if ($Task -in @('Defender','Windows')) {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal $identity
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                $parameters.Verb = 'RunAs'
            }
        }
        $script:ActiveProcess = Start-Process @parameters
        $script:ActiveTask = $Task
        if ($Task -eq 'Scan') {
            $script:HasScan = $false
        }
        $script:States[$script:Index] = 'Läuft'
        $script:Messages[$script:Index] = Get-UiText 'RunningMessage'
        $script:Ui.Status.Text = $script:Messages[$script:Index]
        Set-StatusVisual $script:States[$script:Index]
        $script:DetailLogs[$script:Index] = ''
        $script:Ui.DetailText.Text = ''
        Add-Event ("$Task gestartet.")
        Set-Busy $true
        $script:Timer.Start()
    } catch {
        $script:States[$script:Index] = 'Offen'
        $script:Messages[$script:Index] = Get-UiText 'NotStartedOrCancelled'
        Add-Event ($script:Messages[$script:Index] + ' ' + $_.Exception.Message)
        Set-Busy $false
    }
}

# Locate and open a Lenovo UI; device updates remain inside that application.
function Open-Lenovo([string]$Kind) {
    try {
        if ($Kind -eq 'SystemUpdate') {
            $locations = @()
            foreach ($root in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
                if ($root) {
                    $locations += (Join-Path $root 'Lenovo\System Update\tvsu.exe')
                }
            }
            $target = $locations | Where-Object {
                Test-Path -LiteralPath $_ -PathType Leaf
            } | Select-Object -First 1
            if (-not $target) {
                throw 'Lenovo System Update wurde nicht gefunden. Öffnen Sie Lenovo Vantage über das Startmenü oder verwenden Sie die manuelle Anleitung.'
            }
            # Ausschließlich Benutzeroberfläche starten, keine Installationsparameter.
            Start-Process -FilePath $target -ErrorAction Stop | Out-Null
        } else {
            $app = Get-StartApps | Where-Object {
                $_.Name -match 'Lenovo.*Vantage|Vantage.*Lenovo|^Vantage$'
            } | Select-Object -First 1
            if (-not $app) {
                throw 'Lenovo Vantage wurde nicht gefunden. Suchen Sie im Startmenü nach «Lenovo Vantage» oder nutzen Sie Lenovo System Update.'
            }
            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"shell:AppsFolder\' + $app.AppID + '"') -ErrorAction Stop | Out-Null
        }
        $script:Messages[$script:Index] = Get-ActionMessage 'LenovoOpened'
        Add-Event $script:Messages[$script:Index]
        Show-Step
    } catch {
        [Windows.MessageBox]::Show($_.Exception.Message,'Lenovo-Programm manuell öffnen') | Out-Null
    }
}

# Route stable action IDs from the step data to workers or external tools.
function Invoke-StepAction([string]$Action) {
    switch ($Action) {
        'Windows' {
            Start-Task 'Windows'
        }
        'Scan' {
            Start-Task 'Scan'
        }
        'Install' {
            Start-Task 'Install'
        }
        'Defender' {
            Start-Task 'Defender'
        }
        'Treiber' {
            Open-Target 'ms-settings:windowsupdate-optionalupdates' (Get-ActionMessage 'Treiber')
        }
        'Store' {
            Open-Target 'ms-windows-store://home' (Get-ActionMessage 'Store')
        }
        'Apps' {
            Open-Target 'ms-settings:appsfeatures' (Get-ActionMessage 'Apps')
        }
        'ControlPanel' {
            Open-Target (Join-Path $env:SystemRoot 'System32\appwiz.cpl') (Get-ActionMessage 'ControlPanel')
        }
        'Security' {
            Open-Target 'ms-settings:windowsdefender' (Get-ActionMessage 'Security')
        }
        'LenovoVantage' {
            Start-Task 'LenovoVantage'
        }
        'LenovoSystemUpdate' {
            Start-Task 'LenovoSystemUpdate'
        }
        'LenovoSources' {
            $answer = [Windows.MessageBox]::Show('Ja: Lenovo Vantage im Microsoft Store öffnen. Nein: offizielle Lenovo-Downloadseite für System Update öffnen. Abbrechen: zurück.', 'Manuell installieren', 'YesNoCancel', 'Question')
            if ($answer -eq 'Yes') {
                Open-Target 'ms-windows-store://pdp/?ProductId=9WZDNCRFJ4MV' (Get-ActionMessage 'VantageStore')
            }
            elseif ($answer -eq 'No') {
                Open-Target 'https://support.lenovo.com/downloads/ds012808' (Get-ActionMessage 'LenovoDownload')
            }
        }
        'Vantage' {
            Open-Lenovo 'Vantage'
        }
        'SystemUpdate' {
            Open-Lenovo 'SystemUpdate'
        }
        'WindowsUpdate' {
            Open-Target 'ms-settings:windowsupdate' (Get-ActionMessage 'WindowsUpdate')
        }
        'History' {
            Open-Target 'ms-settings:windowsupdate-history' (Get-ActionMessage 'History')
        }
        'Options' {
            Open-Target 'ms-settings:windowsupdate-options' (Get-ActionMessage 'Options')
        }
    }
}

# Worker polling: read local log/result files without blocking the WPF event loop.
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
                    'Done' {
                        'Automatisch bearbeitet'
                    }
                    'Scanned' {
                        'Suche abgeschlossen'
                    }
                    'ToolReady' {
                        'Programm bereit'
                    }
                    'RestartNeeded' {
                        'Neustart nötig'
                    }
                    default {
                        'Bitte prüfen'
                    }
                }
                if ($script:ActiveTask -eq 'Scan') {
                    $script:HasScan = ($result.Outcome -eq 'Scanned')
                }
            } else {
                $script:States[$script:Index] = 'Bitte prüfen'
                $script:Messages[$script:Index] = Get-UiText 'ResultMissing'
            }
            Add-Event ($script:ActiveTask + ': ' + $script:Messages[$script:Index])
            $script:ActiveProcess.Dispose()
            $script:ActiveProcess = $null
            Set-Busy $false
            Save-Report
            if ($script:ActiveTask -eq 'Windows' -and $result -and $result.Outcome -eq 'RestartNeeded') {
                Begin-RestartCountdown
            }
        }
    } catch {
        $script:Timer.Stop()
        # Den Installationsprozess nicht beenden. Bis zu seinem Ende gesperrt bleiben.
        if ($script:ActiveProcess -and -not $script:ActiveProcess.HasExited) {
            $script:Ui.Status.Text = Get-UiText 'StillRunning'
            $script:Timer.Start()
        } else {
            $script:States[$script:Index] = 'Bitte prüfen'
            $script:Messages[$script:Index] = Get-UiText 'ResultReadFailed'
            Set-Busy $false
        }
    }
})

# Restart lifecycle: persist step results, count down and resume after Windows signs in.
$script:RestartPending = $false
$script:ResumePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WFW\Update-Assistent\Fortsetzen.json'
$script:RestartTimer = New-Object Windows.Threading.DispatcherTimer
$script:RestartTimer.Interval = [TimeSpan]::FromSeconds(1)
# Restore saved results after reboot, leaving Windows updates open for a new check.
function Restore-Session {
    if (Test-Path -LiteralPath $script:ResumePath) {
        try {
            $saved = Get-Content -LiteralPath $script:ResumePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.States.Count -eq 8 -and $saved.Messages.Count -eq 8) {
                $script:States = @($saved.States)
                $script:Messages = @($saved.Messages)
                $script:States[0] = 'Offen'
                $script:Messages[0] = Get-UiText 'Restore'
            }
            Remove-Item -LiteralPath $script:ResumePath -Force
        } catch {
            $script:Messages[0] = Get-UiText 'RestoreFailed'
        }
    }
}

# Cancel the pending countdown and keep the restart requirement visible.
function Stop-RestartCountdown {
    $script:RestartTimer.Stop()
    $script:RestartPending = $false
    $script:Ui.CancelRestart.Visibility = 'Collapsed'
    $script:Messages[0] = Get-UiText 'RestartPostponed'
    $script:States[0] = 'Neustart nötig'
    Set-Busy $false
    Add-Event 'Der Benutzer hat den automatischen Neustart verschoben.'
    Save-Report
}

# Show the two-minute restart countdown and allow the user to postpone it.
function Begin-RestartCountdown {
    $script:RestartDeadline = (Get-Date).AddSeconds(120)
    $script:RestartPending = $true
    Set-Busy $true
    $script:Ui.BusyBar.Visibility = 'Collapsed'
    $script:Ui.CancelRestart.Visibility = 'Visible'
    $script:Ui.Status.Text = Get-UiText 'Restart120'
    $script:Window.WindowState = 'Normal'
    $script:Window.Activate() | Out-Null
    $script:RestartTimer.Start()
}
$script:RestartTimer.Add_Tick({
    try {
        $left = [int][Math]::Ceiling(($script:RestartDeadline - (Get-Date)).TotalSeconds)
        if ($left -gt 0) {
            $script:Ui.Status.Text = (Get-UiText 'RestartCountdown') -f $left
            return
        }
        $script:RestartTimer.Stop()
        @{
            States = $script:States;
            Messages = $script:Messages;
            Time = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ResumePath -Encoding UTF8
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $command = '"{0}" -NoProfile -STA -ExecutionPolicy RemoteSigned -File "{1}" -Resume' -f $exe,$script:ScriptPath
        # RunOnce ist auf 260 Zeichen begrenzt. Keine stille, unzuverlässige Registrierung.
        if ($command.Length -gt 260) {
            throw 'Der Programmpfad ist zu lang für die automatische Wiederaufnahme. Bitte Paket in einen kürzeren Ordner verschieben oder manuell neu starten.'
        }
        $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        if (-not (Test-Path $runOnce)) {
            New-Item $runOnce -Force | Out-Null
        }
        New-ItemProperty -Path $runOnce -Name WFWUpdateAssistant -Value $command -PropertyType String -Force | Out-Null
        Save-Report
        # Eigener Countdown statt shutdown /t 120: /t > 0 würde /f implizieren.
        # /t 0 ohne /f lässt Anwendungen den Neustart blockieren.
        & (Join-Path $env:SystemRoot 'System32\shutdown.exe') /r /t 0 /d p:2:17
        if ($LASTEXITCODE -ne 0) {
            throw 'Windows konnte den Neustart nicht starten. Bitte speichern und über das Startmenü selbst neu starten.'
        }
        $script:RestartPending = $false
        $script:Ui.CancelRestart.Visibility = 'Collapsed'
        $script:Messages[0] = Get-UiText 'RestartStarted'
        Set-Busy $false
    } catch {
        $script:RestartPending = $false
        $script:Ui.CancelRestart.Visibility = 'Collapsed'
        $script:States[0] = 'Bitte prüfen'
        $script:Messages[0] = $_.Exception.Message
        Set-Busy $false
    }
})
$script:Ui.CancelRestart.Add_Click({
    Stop-RestartCountdown
})

$script:NavStatus = @()
# Build sidebar controls and retain references for status and language refreshes.
foreach ($step in $script:Steps) {
    $item = New-Object Windows.Controls.ListBoxItem
    $row = New-Object Windows.Controls.Grid
    $columnIcon = New-Object Windows.Controls.ColumnDefinition
    $columnIcon.Width = [Windows.GridLength]::Auto
    $columnText = New-Object Windows.Controls.ColumnDefinition
    $columnText.Width = New-Object Windows.GridLength -ArgumentList 1,([Windows.GridUnitType]::Star)
    $row.ColumnDefinitions.Add($columnIcon)
    $row.ColumnDefinitions.Add($columnText)
    $icon = New-Object Windows.Controls.TextBlock
    $icon.Text = [string]($script:Ui.Navigation.Items.Count + 1)
    # Numbers need a text font; icon fonts do not reliably contain digit glyphs.
    $icon.Style = $script:Window.FindResource('StepNumberText')
    $icon.Width = 24
    $icon.Margin = '0'
    $icon.TextAlignment = 'Center'
    $icon.VerticalAlignment = 'Center'
    $badge = New-Object Windows.Controls.Border
    $badge.Width = 32
    $badge.Height = 32
    $badge.CornerRadius = New-Object Windows.CornerRadius -ArgumentList 16
    $badge.Background = $script:Window.FindResource('PrimarySoftBrush')
    $badge.Margin = '0,0,12,0'
    $badge.VerticalAlignment = 'Top'
    $badge.Child = $icon
    [Windows.Controls.Grid]::SetColumn($icon, 0)
    $stack = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($stack, 1)
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $step.Title -replace '^\d+ · ', ''
    $title.FontWeight = 'SemiBold'
    $title.TextWrapping = 'Wrap'
    $caption = New-Object Windows.Controls.TextBlock
    $caption.Text = Get-StateText 'Offen'
    $caption.FontSize = 11
    $caption.Margin = '0,4,0,0'
    $caption.TextWrapping = 'Wrap'
    $row.Children.Add($badge) | Out-Null
    $stack.Children.Add($title) | Out-Null
    $stack.Children.Add($caption) | Out-Null
    $row.Children.Add($stack) | Out-Null
    $item.Content = $row
    $item.Tag = @{
        Title = $title;
        Caption = $caption;
        Icon = $icon
    }
    $script:Ui.Navigation.Items.Add($item) | Out-Null
    $script:NavStatus += @{
        Caption = $caption;
        Icon = $icon
    }
}
# UI event bindings: navigation, confirmations, help, reports and shutdown handling.
$script:Ui.Navigation.Add_SelectionChanged({
    if ($script:Ui.Navigation.SelectedIndex -ge 0 -and -not $script:Busy) {
        $script:Index = $script:Ui.Navigation.SelectedIndex
        Show-Step
    }
})
$script:Ui.LanguageSwitch.Add_SelectionChanged({
    $selected = $script:Ui.LanguageSwitch.SelectedItem
    if ($selected -and $selected.Tag) {
        Set-Language ([string]$selected.Tag)
    }
})
$script:Ui.Confirm.Add_Click({
    $script:States[$script:Index] = if ($script:Ui.Confirm.IsChecked) {
        'Benutzer bestätigt'
    } else {
        'Offen'
    }
    $script:Messages[$script:Index] = if ($script:Ui.Confirm.IsChecked) {
        Get-UiText 'ManualConfirmed'
    } else {
        Get-UiText 'NotConfirmed'
    }
    Add-Event ($script:Steps[$script:Index].Title + ': ' + $script:States[$script:Index])
    Show-Step
    Save-Report
})
$script:Ui.Back.Add_Click({
    if ($script:Index -gt 0) {
        $script:Ui.Navigation.SelectedIndex--
    }
})
$script:Ui.Next.Add_Click({
    if ($script:Index -lt 7) {
        $script:Ui.Navigation.SelectedIndex++
    }
    else {
        Save-Report;
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"' + (Join-Path $script:SessionDirectory 'Zusammenfassung.txt') + '"')
    }
})
$script:Ui.Help.Add_Click({
    [Windows.MessageBox]::Show((Get-UiText 'HelpDialog'), (Get-UiText 'HelpTitle'), 'OK', 'Information') | Out-Null
})
$script:Ui.Report.Add_Click({
    try {
        Save-Report;
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $script:SessionDirectory + '"')
    }
    catch {
        [Windows.MessageBox]::Show((Get-UiText 'ReportOpenFailed'), (Get-UiText 'ReportTitle')) | Out-Null
    }
})
$script:Ui.Guide.Add_Click({
    $path = Join-Path (Split-Path $script:BaseDirectory) 'Anleitung.pdf'
    if (Test-Path -LiteralPath $path) {
        try {
            Start-Process -FilePath $path -ErrorAction Stop | Out-Null
        }
        catch {
            [Windows.MessageBox]::Show((Get-UiText 'GuideOpenFailed'), (Get-UiText 'GuideTitle')) | Out-Null
        }
    }
    else {
        [Windows.MessageBox]::Show((Get-UiText 'GuideMissing'), (Get-UiText 'GuideTitle')) | Out-Null
    }
})
$script:Window.Add_Closing({
    param($sender,$eventArgs)
    if ($script:RestartPending) {
        Stop-RestartCountdown
    }
    if ($script:Busy) {
        $eventArgs.Cancel = $true
        [Windows.MessageBox]::Show((Get-UiText 'BusyClose'), (Get-UiText 'BusyCloseTitle')) | Out-Null
    } else {
        $script:Timer.Stop();
        try {
            Save-Report
        } catch {
        }
    }
})
# Initial render and modal window lifetime. Release the single-instance mutex on exit.
Apply-StaticText
if ($Resume) {
    Restore-Session
}
$script:Ui.Navigation.SelectedIndex = 0
Add-Event 'Assistent gestartet. Keine Updates automatisch gestartet.'
Save-Report
try {
    $script:Window.ShowDialog() | Out-Null
} finally {
    $script:GuiMutex.ReleaseMutex();
    $script:GuiMutex.Dispose()
}
