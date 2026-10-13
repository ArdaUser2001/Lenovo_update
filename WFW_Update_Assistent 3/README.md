# WFW Update-Assistent 1.3

Ein geführter Update-Assistent für Windows 11 mit deutscher und englischer Oberfläche.

## Start

Den ganzen Ordner lokal entpacken. Arbeit speichern, andere Programme schließen,
Ladekabel und Internet verbinden. [UPDATE-ASSISTENT-STARTEN.cmd](./UPDATE-ASSISTENT-STARTEN.cmd)
doppelt anklicken und **Computer aktualisieren** wählen.

Nach einer Bestätigung laufen Virenschutz, unterstützte Programmupdates über
winget, Windows-Updates und empfohlene Treiber nacheinander. Optionale Treiber
können vor dem Start per Häkchen ergänzt werden. Der Assistent zeigt das Ergebnis
jeder Aufgabe und setzt einen registrierten Durchlauf nach Neustart und Anmeldung
fort. Windows kann Administratorrechte anfordern.

Store-Apps, Lenovo-Firmware und freiwilliges Aufräumen bleiben separate Schritte.
Details zur Bedienung stehen in [START-HIER.txt](./START-HIER.txt).
Die vorhandene [PDF-Anleitung](./Anleitung.pdf) beschreibt die bisherige manuelle Schrittfolge.

## Prüfung

Die synthetischen Tests installieren keine Updates und ändern keine Systemeinstellungen:

```powershell
pwsh -NoProfile -File IT/Test-QuickRun.ps1
```

Unter Windows zusätzlich die Oberfläche und Paketstruktur prüfen:

```powershell
powershell.exe -NoProfile -STA -File IT/Validieren.ps1
```

Echte Windows-Updates, WPF, UAC und die Wiederaufnahme müssen noch auf einem
Windows-Testgerät geprüft werden. Siehe [IT-Testplan](./IT/IT-Testplan.md) und
[Prüfbericht](./IT/Pruefbericht.txt). Vor Verteilung die PowerShell-Dateien mit einem
vertrauenswürdigen Zertifikat signieren.
