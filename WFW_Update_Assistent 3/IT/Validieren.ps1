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

# Check that the main XAML is well-formed XML.
[xml]$xaml = Get-Content -LiteralPath (Join-Path $program 'Oberflaeche.xaml') -Raw -Encoding UTF8

# Verify that the packaged launcher, guide, logo and worker modules exist.
foreach ($name in @('UPDATE-ASSISTENT-STARTEN.cmd','Anleitung.pdf','START-HIER.txt','Programm/Assets/Logo.png','Programm/Module/Updates.psm1','Programm/Module/WindowsUpdate.psm1','Programm/Module/LenovoTools.psm1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name))) {
        throw ('Datei fehlt: '+$name)
    }
}
Write-Output 'PowerShell-Syntax und Paketstruktur sind in Ordnung. Windows-Funktionstest nach IT-Testplan.md bleibt erforderlich.'
