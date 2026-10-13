# WFW Update-Assistent 1.2

Ardawan Khosronezhad · IT Germany · 30. September 2026

Pilotfassung für Windows 11 Pro auf nicht zentral verwalteten Geräten.

## Paket und Einstieg

| Datei/Ordner | Zweck |
|---|---|
| `UPDATE-ASSISTENT-STARTEN.cmd` | Einziger vorgesehener Doppelklick-Einstieg |
| `Anleitung.pdf` | Vollständige manuelle KB mit optionalem Assistentenabschnitt |
| `START-HIER.txt` | Kurzanleitung und Hilfe bei Startproblemen |
| `Programm/Update-Assistent.ps1` | GUI, Prozessüberwachung, Countdown und Wiederaufnahme |
| `Programm/Oberflaeche.xaml` | WPF-Layout und Darstellung |
| `Programm/Module/Updates.psm1` | Worker, winget und Defender |
| `Programm/Module/WindowsUpdate.psm1` | Konfigurationsprüfung und Windows Update Agent |
| `Programm/Assets/Logo.png` | Vorhandenes WFW-Logo |
| `IT/Validieren.ps1` | Native PowerShell-Syntax- und Strukturprüfung ohne Installation |
| `IT/Pruefbericht.txt` | Tatsächlich durchgeführte statische Prüfungen |

## Windows-Update-Verhalten

Die eigene Schaltfläche fragt zunächst nach Zustimmung für Einstellungen,
Update-Lizenzbedingungen, Installation und automatischen Neustart bei Bedarf.
Nur der Windows-Worker wird dafür über UAC erhöht, die Oberfläche bleibt im
Benutzerkontext. Der Defender-Worker kann ebenfalls UAC anfordern. winget
bleibt im ursprünglichen Benutzerkontext. Die GUI verhindert eine zweite
Instanz im selben Benutzerkonto.

Vor Änderungen erfolgt eine konservative Verwaltungserkennung: Domäne,
Entra-Join, erkennbare MDM-Einschreibung, WSUS, Update-Zugriffsbeschränkungen
und lokale Registry.pol zusammen mit Windows-Updatevorgaben. Unklarer
Join-Status wird als Fehler behandelt. Diese Erkennung ist keine umfassende
Inventarisierung sämtlicher Verwaltungsprodukte. Bei einem Treffer wird der
Vorgang beendet und auf den passenden manuellen/Firmenweg verwiesen.

Eine erkennbare aktive Update-Pause wird nicht mit undokumentierten
Registryschreibzugriffen aufgehoben. Benutzer sollen in Windows Update
„Updates fortsetzen“ wählen und den Assistenten erneut starten.

### Nur notwendige Konfigurationsänderungen

Unter `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`:

- Fehlende `NoAutoUpdate`- und `AUOptions`-Werte: Windows-Standard, keine Anlage.
- `NoAutoUpdate=0` und `AUOptions=4`: keine Änderung.
- Vorhandenes, abweichendes `NoAutoUpdate`: auf `0` setzen.
- Vorhandenes, abweichendes `AUOptions`: auf `4` setzen.
- Deaktivierte Dienste `wuauserv` oder `BITS`: auf `Manual` zurücksetzen;
  laufende Dienste nicht erneut starten, gestoppte bei Bedarf starten.

Die ursprünglichen Werte und Dienstzustände werden vor Schreibzugriffen in
`Einstellungen-vorher.json` gespeichert. Konfigurationswerte werden danach
zurückgelesen. Das belegt den geschriebenen Zustand, nicht den Zeitpunkt
der nächsten Windows-Planung. Rücknahme bei Bedarf durch IT anhand der
Originalwerte; keine pauschale Löschung vorhandener Richtlinien.

Die ältere COM-Methode `AutomaticUpdatesSettings.Save()` wird ausdrücklich
nicht verwendet: Seit Windows 10 meldet sie Erfolg, ändert aber nichts.
Es werden weder aktive Zeiten noch die grafische Option für frühzeitige
optionale Updates noch dauerhafte Windows-Neustartoptionen geändert.

### Suche und Installation

Windows Update Agent (COM), Standard-Updatequelle:
`IsInstalled=0 and IsHidden=0 and Type='Software' and AutoSelectOnWebSites=1`.
Zusätzlich werden BrowseOnly, interaktive Pakete und die Klassifizierung
Upgrades (`3689bdc8-b205-4af4-8d4a-a63924c5e9d5`) ausgeschlossen. Treiber und
Firmware werden nicht über diesen Schritt installiert. Die Updateauswahl
ist kein Ersatz für eine Prüfung aller optionalen Angebote in Einstellungen.

Pakete werden einzeln heruntergeladen und installiert, damit sich exklusive
Installationen nicht gegenseitig ausschließen. Download- und Installations-
ergebnisse werden geprüft. Ein bereits erforderlicher Neustart beendet den
Durchlauf vor weiteren Installationen. Wenn kein Neustart nötig ist, folgt
eine Kontrollsuche. Weitere Angebote bleiben sichtbar als „Bitte prüfen“.
Es gibt keine Endlosschleife und keine automatische Anmeldung nach Neustart.

Bei Fehlern wird kein automatischer Neustart gestartet, selbst wenn einige
Pakete bereits installiert wurden. Ein notwendiger manueller Neustart wird
in der Meldung genannt. Nach erfolgreichem Durchlauf mit Neustartbedarf
beginnt der GUI-Countdown von 120 Sekunden.

### Neustart und Wiederaufnahme

Der Countdown liegt in der GUI und kann verschoben werden. Schließen der
GUI während des Countdowns hebt ihn ebenfalls auf. Es wird kein
`shutdown /t 120` eingesetzt, weil ein positives Timeout laut Microsoft
implizit `/f` aktiviert. Nach Ablauf wird `shutdown /r /t 0` ohne `/f`
aufgerufen. Programme können den Neustart damit blockieren; kein
Versprechen eines erzwungenen oder garantiert vollautomatischen Neustarts.

Vor dem Neustart: lokaler Sitzungsstand `Fortsetzen.json` und ein HKCU-
RunOnce-Eintrag `WFWUpdateAssistant`, der dieselbe GUI mit `-Resume` startet.
Keine administrative Hintergrundaufgabe oder gespeicherten Zugangsdaten.
Der Programmordner muss erhalten bleiben. Nach Anmeldung am selben Konto
öffnet sich die GUI und der Benutzer startet die nächste Prüfung. RunOnce
kann durch Anmelde-/Sicherheitsrichtlinien verzögert oder blockiert werden;
die Startdatei bleibt der Rückfallweg. Lange Befehlszeilen über 260 Zeichen
führen zu einem Hinweis statt zu einer unzuverlässigen Registrierung.

## Verbleibende Windows-Abnahme

Die Entwicklung lief auf Linux. PowerShell-Grammatik, XAML-Struktur und
Paketkonsistenz wurden statisch geprüft; WPF, UAC, Registry und echte
Installationen wurden hier nicht ausgeführt. Vor Benutzerverteilung auf
einem Lenovo-Testgerät prüfen:

| Test | Erwartung |
|---|---|
| Paketstart, Leerzeichen/Umlaute im Pfad | Oberfläche, Module, Logo und PDF funktionieren |
| Zweiter Start | Hinweis auf bereits geöffnete Instanz |
| Tastatur und 100/150/200 % Skalierung | Navigation, Status und Aktionen erreichbar; Inhalt scrollt |
| Windows-Knopf, Bestätigung ablehnen | Keine Änderung/Installation/Neustart |
| UAC ablehnen | Kein falscher Erfolg, manuelle Alternative |
| Standardeinstellungen ohne AU-Werte | Keine neuen AU-Werte; Protokoll „keine Einstellungen geändert“ |
| NoAutoUpdate=0, AUOptions=4 | Keine erneuten Schreibzugriffe |
| Abweichende lokale AU-Werte auf unverwaltetem Testgerät | Gesichert, korrigiert, zurückgelesen; zweiter Lauf ohne Änderung |
| Dienst deaktiviert vs. schon korrekt | Nur deaktivierte Dienste umkonfiguriert |
| Domäne, Entra, MDM, WSUS, lokale Update-GPO | Abbruch vor Konfigurationsänderungen |
| Aktive Update-Pause | Aufforderung, Windows-Updates manuell fortzusetzen |
| Netzteil fehlt | Keine Update-Installation; verständlicher Hinweis |
| Keine Updates, kein Neustart | Kein Download, keine Installation, kein Countdown |
| Update verfügbar | Download/Installation/ResultCode einzeln im Protokoll |
| Optionales/Feature-/Treiberupdate | Nicht automatisch installiert, weiterer manueller Weg |
| Offline oder Teilfehler | Fehlerstatus; kein pauschaler Erfolg oder automatischer Neustart |
| Neustart schon vor Installation nötig | Keine weitere Installation, Countdown |
| Countdown verschieben oder GUI schließen | Kein Neustart durch Assistenten |
| Countdown vollständig | Normaler Neustart; ungespeicherte Testdatei kann ihn blockieren |
| Wiederanmeldung mit gleichem Konto | GUI öffnet; Windows-Bereich fordert erneute Prüfung |
| RunOnce blockiert, Pfad zu lang/verschoben | Manueller Neustart/Start möglich, verständlicher Hinweis |
| Andere Bereiche nach Refactoring | winget, Defender, Store, Lenovo und manuelle Bestätigungen funktionieren |
| Programmupdate noch aktiv | Neue Aktionen gesperrt; kein paralleler Windows-Neustart |
| Signatur/AllSigned/AppLocker/WDAC | Bestehende Vorgaben werden nicht umgangen |

Vor Verteilung PS1/PSM1-Dateien mit einem auf Zielrechnern vertrauenswürdigen
Code-Signing-Zertifikat signieren. `RemoteSigned` wird nur pro Prozess gesetzt;
Gruppenrichtlinien haben Vorrang. Keine dauerhafte Lockerung der
PowerShell-Ausführungsrichtlinie. Signatur nach jeder Codeänderung erneuern.

## Herstellerquellen

- [WUA Suche, Download und Installation](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-updates)
- [Automatische Updates konfigurieren](https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings)
- [Nicht mehr unterstützte Settings.Save-Methode](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iautomaticupdatessettings-save)
- [shutdown und implizites Erzwingen bei Timeout](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown)
- [Run und RunOnce](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)
- [WinGet upgrade](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade)
- [Defender-Signaturen](https://learn.microsoft.com/en-us/powershell/module/defender/update-mpsignature)


## Neu in Version 1.2: Lenovo-Tools installieren

`Programm/Module/LenovoTools.psm1` enthält Erkennung und Installation.
Vantage: exakte Store-ID `9WZDNCRFJ4MV`, Quelle `msstore`.
System Update: exakte ID `Lenovo.SystemUpdate`, Quelle `winget`.
Die automatische Installation läuft nur auf einem als Lenovo erkannten
Gerät, im ursprünglichen Benutzerkonto. Installer können UAC anfordern.
Store-Anmeldung und Netzverbindung können erforderlich sein. Keine
Zugangsdaten werden gespeichert und keine Schutzprüfung deaktiviert.

Vantage wird über das registrierte Appx-Paket bzw. den Startmenüeintrag
geprüft; System Update über Standardpfade und Lenovo-Uninstall-Einträge.
Eine vorhandene Installation wird nicht erneut installiert. WinGet erhält
zusätzlich `--no-upgrade`. Nach Exitcode 0 wird die Erkennung erneut geprüft.
`Programm bereit` bestätigt nur das Tool, nicht die Geräte-/Firmwareupdates.
Bei Store-/WinGet-Fehlern stehen im GUI manuelle offizielle Bezugsquellen zur
Verfügung; deren Öffnen gilt ausdrücklich nicht als Installationserfolg.

Zusätzliche Pilotprüfungen: beide Tools einzeln auf dem blanken Image
installieren; bei vorhandenem Tool keine Neuinstallation; Vantage im
richtigen Benutzerprofil; fehlender App-Installer; Store deaktiviert;
Offlinefall; UAC abgelehnt; Nicht-Lenovo-Gerät; Exitcode 0 ohne erkennbares
Programm. Danach Öffnen und Ersteinrichtung prüfen. System Update auf dem
konkreten Modell anhand der Lenovo-Kompatibilitätsangaben testen.
Alle PS1- und PSM1-Dateien vor Verteilung erneut signieren.

Quellen:
- https://apps.microsoft.com/detail/9wzdncrfj4mv
- https://support.lenovo.com/downloads/ds012808
- https://github.com/microsoft/winget-pkgs/tree/master/manifests/l/Lenovo/SystemUpdate
- https://learn.microsoft.com/en-us/windows/package-manager/winget/install

## Bedienung für Windows-Einsteiger

Diese Prüfungen sind auf Windows noch auszuführen:

- Beim ersten Öffnen beginnt die Anleitung mit Schritt 1; keine Aktion startet automatisch.
- Alle acht Schritte zeigen nummerierte Anweisungen und einen nächsten Handlungsschritt.
- Bei 100/150/200 % Skalierung und kleinem Fenster bleiben Aktionsbeschriftungen lesbar; Inhalte und die zusätzlichen Hilfeschaltflächen sind erreichbar.
- Store oder Windows-Einstellungen öffnen und mithilfe der Bedienungshilfe zum Assistenten zurückkehren. Das Öffnen allein bestätigt keinen Schritt.
- Weitergehen ohne Häkchen lässt den Schritt offen, auch in der Zusammenfassung. Zurückgehen erhält die bisherigen Zustände.
- Nach erfolgreicher Programmsuche wird die Installationsschaltfläche hervorgehoben. Bei laufender Aktion bleibt die Navigation gesperrt.
- Hilfe während laufender Updates öffnen; der Vorgang läuft weiter.
- Windows- und Defender-Aktion starten den Worker über WindowsPowerShell/v1.0; UAC-Abbruch zeigt keinen Erfolg.
- Countdown verschieben und nach Neustart fortsetzen; die Windows-Prüfung bleibt Schritt 1.
- Den gesamten Ablauf mit einer Person ohne Windows-Vorkenntnisse durchgehen; insbesondere Fensterwechsel, Rückfragen und offene Schritte erklären lassen.

## Version 1.3: gemeinsamer Update-Durchlauf (13. Oktober 2026)

«Computer aktualisieren» startet nach einer einzigen Bestätigung die Aufgaben
DefenderSecure → Install → Windows → Drivers. winget läuft im ursprünglichen
Benutzerkonto; Windows/Defender/Treiber laufen bei Bedarf mit UAC. Es werden
keine Kennwörter gespeichert. Store-Apps, Aufräumen und Lenovo-Firmware bleiben
separate Prüfungen. Optionale Treiber benötigen das Häkchen vor dem Start.

QuickRun.psm1 enthält die Zustandsmaschine; QuickRun.Gui.ps1 bindet sie an die
bestehende WPF-Oberfläche. Gemeinsamer-Durchlauf.json wird atomar im lokalen
Benutzerprofil gespeichert. Ergebnisdateien und worker.json ermöglichen die
Wiederanbindung an einen noch laufenden Prozess statt eines zweiten Installers.
Nach registriertem Neustart startet RunOnce dieselbe Oberfläche mit -Resume
-ResumeQuickRun. Nur ein neuer Boot und höchstens sieben Tage alte Zustimmung
erlauben automatisches Fortsetzen. Ein verschobener Neustart benötigt die
Fortsetzen-Schaltfläche nach einem echten Neustart. Drei Neustarts begrenzen
den Lauf. Fehler mit Neustartbedarf führen zum manuellen Neustart.

Treiber: Windows Update Agent, Type='Driver', nicht installiert und nicht
ausgeblendet. Standardmäßig nur IsAssigned und nicht BrowseOnly. Firmware,
BIOS/UEFI, interaktive Updates, fehlende Hardware-IDs und mehrdeutige Angebote
bleiben manuell. Pro Hardware-ID wird höchstens ein eindeutiges Paket gewählt;
ein empfohlenes Paket hat Vorrang vor einer optionalen Alternative.

Defender: nur aktiver Normal-Modus. Schutzinformationen aktualisieren; erlaubte
lokale Echtzeit-, Verhaltens-, Download- und Dateischutz-Einstellungen aktivieren
und den Status danach prüfen. Manipulationsschutz, Geräteverwaltung und
Defender-Richtlinien verhindern lokale Einstellungsänderungen. Ein anderer
Virenschutz wird nicht ersetzt. Nicht bestätigter Schutz bleibt «Bitte prüfen».

Auf Windows vor Verteilung ausführen:

| Prüfung | Erwartung |
|---|---|
| Start DE/EN, kleine Fenster, 100/150/200 % Skalierung | Startknopf, optionales Häkchen und alle vier Ergebnisse lesbar; Inhalt scrollt |
| Bestätigung ablehnen | Keine Installationen, keine Einstellungsänderungen |
| Ladekabel fehlt | Kein gemeinsamer Durchlauf gestartet |
| Ein Start mit Updates | Vier Aufgaben laufen nacheinander, keine erneute App-Suche durch den Benutzer |
| UAC bei einer Aufgabe ablehnen | Diese Aufgabe «Bitte prüfen»; unabhängige Aufgaben laufen weiter |
| Domäne/Entra/MDM/Updatevorgaben | Keine Umgehung; Windows/Treiber melden den Firmenweg |
| Defender lokal deaktivierte unterstützte Funktionen | Nur erlaubte Schutzfunktionen aktivieren; Status zurücklesen |
| Manipulationsschutz, Richtlinie, anderer Antivirus | Keine Umgehung/Ersetzung; verständliches Ergebnis |
| Keine Treiber, empfohlene Treiber, optionale Treiber | Auswahl stimmt mit dem Häkchen überein; keine automatische Firmware |
| Mehrere optionale Pakete für dieselbe Hardware-ID | Manuelle Auswahl statt mehrerer Installationen |
| Erfolgreiches Windows-/Treiberupdate mit Neustartbedarf | Countdown, Checkpoint, Anmeldung, Wiederprüfung derselben Aufgabe; frühere Aufgaben nicht wiederholen |
| Teilfehler mit Neustartbedarf | Kein automatischer Neustart; nach manuellem Neustart bestätigtes Fortsetzen |
| Countdown verschieben oder Fenster schließen | Kein Neustart; Fortschritt erhalten; Fortsetzen erst nach neuem Boot |
| RunOnce blockiert oder Pfad länger als 260 Zeichen | Kein unzuverlässiger automatischer Neustart; manuell neu starten und Assistent öffnen |
| Nach drei Neustarts weiter Neustart nötig | Automatischer Lauf angehalten; Prüfung durch Benutzer/IT |
| GUI unterbrochen, Worker noch aktiv | An bestehenden Prozess anbinden; keine zweite Installation |
| Worker ohne result.json, beschädigter Checkpoint | Kein falscher Erfolg; Ergebnisse bzw. Protokoll prüfen |
| Älter als sieben Tage gespeicherte Neustartzustimmung | Kein automatisches Fortsetzen |
| Fehler bei einer Aufgabe | Gesamtergebnis bleibt «Bitte prüfen»; erfolgreiche Einzelaufgaben sichtbar |
| Bestehende Einzelaktionen und deren Neustart | Einzelaktionen funktionieren; keine versehentliche Wiederaufnahme eines alten gemeinsamen Laufs |

IT/Test-QuickRun.ps1 prüft Ablauf, Checkpoints, Auswahlregeln, GUI-Ergebnisrouting
und Defender-Verhalten mit simulierten Systemfunktionen. Diese Tests installieren
keine echten Updates und ersetzen die obigen Windows-Prüfungen nicht.
Neue und geänderte PowerShell-Dateien vor Benutzerverteilung erneut signieren.
