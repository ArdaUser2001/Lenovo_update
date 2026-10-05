#requires -Version 5.1
# Prüft das Paket, startet keine GUI, schreibt keine Systemeinstellungen.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$program = Join-Path $root 'Programm'

# Parse every PowerShell module without executing it.
foreach ($path in Get-ChildItem -LiteralPath $program -Recurse -File | Where-Object {
    $_.Extension -in @('.ps1','.psm1')
}) {
    $tokens = $null;
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) {
        $parseErrors | Format-List;
        throw ('Syntaxfehler: '+$path.Name)
    }
}

# Parse the inline launcher preflight too; it must work before unsigned files can load.
$launcher = Get-Content -LiteralPath (Join-Path $root 'UPDATE-ASSISTENT-STARTEN.cmd') -Raw
$commandLines = @()
$collecting = $false
foreach ($line in ($launcher -split '\r?\n')) {
    if ($line -match ' -Command \^$') { $collecting = $true; continue }
    if ($collecting) {
        $part = $line.Trim()
        $continued = $part.EndsWith('^')
        if ($continued) { $part = $part.Substring(0, $part.Length - 1).TrimEnd() }
        if (-not ($part.StartsWith('"') -and $part.EndsWith('"'))) {
            throw 'Unerwartetes Format im PowerShell-Startbefehl.'
        }
        $commandLines += $part.Substring(1, $part.Length - 2)
        if (-not $continued) { break }
    }
}
if ($commandLines.Count -eq 0) { throw 'Die Startpruefung fehlt im Launcher.' }
$null = [scriptblock]::Create(($commandLines -join ' '))

# Check that the main XAML is well-formed XML.
[xml]$xaml = Get-Content -LiteralPath (Join-Path $program 'Oberflaeche.xaml') -Raw -Encoding UTF8

# Verify that the packaged launcher, guide, logo and worker modules exist.
foreach ($name in @('UPDATE-ASSISTENT-STARTEN.cmd','Anleitung.pdf','START-HIER.txt','Programm/Assets/Logo.png','Programm/Module/Updates.psm1','Programm/Module/WindowsUpdate.psm1','Programm/Module/LenovoTools.psm1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name))) {
        throw ('Datei fehlt: '+$name)
    }
}
# Instantiate the actual WPF resources and window without showing it or running updates.
# XML parsing alone cannot detect resource/property type mismatches such as Double vs GridLength.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Bitte mit Windows PowerShell im STA-Modus ausführen: powershell.exe -NoProfile -STA -File IT\Validieren.ps1'
}
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
function Read-ValidationXaml([string]$Path) {
    $document = [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $document
    try {
        [Windows.Markup.XamlReader]::Load($reader)
    } finally {
        $reader.Close()
    }
}
$application = [Windows.Application]::Current
if (-not $application) { $application = New-Object Windows.Application }
$loadedDictionaries = @()
$window = $null
try {
    foreach ($name in @('Icons.xaml','Theme.xaml','Styles.xaml')) {
        $dictionary = Read-ValidationXaml (Join-Path $program ('Oberflaeche\' + $name))
        $application.Resources.MergedDictionaries.Add($dictionary)
        $loadedDictionaries += $dictionary
    }
    $window = Read-ValidationXaml (Join-Path $program 'Oberflaeche.xaml')
    foreach ($iconKey in @('IconRefresh','IconSearch','IconDownload','IconExternal','IconShield','IconApps','IconDevice','IconArrowLeft','IconArrowRight','IconHelp','IconDocument')) {
        if ($window.FindResource($iconKey) -isnot [Windows.Media.Geometry]) {
            throw ('Ungueltige Icon-Geometrie: ' + $iconKey)
        }
    }
    if ($window.FindResource('NavigationWidth') -isnot [Windows.GridLength]) {
        throw 'NavigationWidth muss vom Typ System.Windows.GridLength sein.'
    }
} finally {
    if ($window) { $window.Close() }
    foreach ($dictionary in $loadedDictionaries) {
        $application.Resources.MergedDictionaries.Remove($dictionary) | Out-Null
    }
}
Write-Output 'PowerShell-Syntax, Paketstruktur und WPF-Laden sind in Ordnung. Windows-Funktionstest nach IT-Testplan.md bleibt erforderlich.'
