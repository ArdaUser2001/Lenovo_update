#requires -Version 5.1
# Run on macOS/Windows PowerShell. All tests are synthetic; no real updates or setting changes.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module (Join-Path $root 'Programm/Module/QuickRun.psm1') -Force
Import-Module (Join-Path $root 'Programm/Module/WindowsUpdate.psm1') -Force
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Result([string]$Task,[string]$Outcome='Done',[bool]$Reboot=$false) {
    [pscustomobject]@{Task=$Task;Outcome=$Outcome;Message='Synthetic test';RebootRequired=$Reboot}
}
$plan=New-QuickRunPlan -BootId 'boot-1'
foreach ($task in @('DefenderSecure','Install','Windows','Drivers')) {
    Assert ((Get-QuickRunTask $plan) -eq $task) 'Tasks must run in order.'
    Set-QuickRunResult $plan (Result $task)
}
Assert ($plan.Status -eq 'Complete' -and $plan.Results.Count -eq 4) 'All four results must be retained.'
Assert (-not (Get-QuickRunTask $plan)) 'A completed run must launch no more workers.'
$plan=New-QuickRunPlan -BootId 'boot-1'
Set-QuickRunResult $plan (Result 'DefenderSecure' 'Attention')
Assert ((Get-QuickRunTask $plan) -eq 'Install') 'One failed step must not hide or prevent independent steps.'
Set-QuickRunResult $plan (Result 'Install')
Set-QuickRunResult $plan (Result 'Windows' 'RestartNeeded' $true)
Assert ($plan.Status -eq 'AwaitingRestart' -and $plan.Stage -eq 2) 'Restart must preserve the interrupted stage.'
Assert (-not (Get-QuickRunTask $plan)) 'No worker may start while waiting for reboot.'
$rejected=$false
try { Resume-QuickRunPlan $plan 'boot-1' } catch {$rejected=$true}
Assert $rejected 'Postponed reboot must not resume on the same boot.'
Resume-QuickRunPlan $plan 'boot-2'
Assert ((Get-QuickRunTask $plan) -eq 'Windows') 'Resume must not repeat prior antivirus or application updates.'
Set-QuickRunResult $plan (Result 'Windows' 'Attention' $true)
Assert $plan.ManualRestartOnly 'Partial installation errors must never trigger an automatic reboot.'
Resume-QuickRunPlan $plan 'boot-3'
Set-QuickRunResult $plan (Result 'Windows' 'RestartNeeded' $true)
Resume-QuickRunPlan $plan 'boot-4'
Set-QuickRunResult $plan (Result 'Windows' 'RestartNeeded' $true)
Assert ($plan.Status -eq 'Paused' -and $plan.Restarts -eq 3) 'Restart loops must stop after three reboots.'
$plan=New-QuickRunPlan -BootId 'boot-1'
$rejected=$false
try { Set-QuickRunResult $plan (Result 'Windows') } catch {$rejected=$true}
Assert ($rejected -and $plan.Stage -eq 0) 'Mismatched worker results must not advance progress.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('wfw-test-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $plan=New-QuickRunPlan -IncludeOptionalDrivers $true -BootId 'boot-1'
    Set-QuickRunResult $plan (Result 'DefenderSecure')
    Write-QuickRunPlan $plan $temp
    $restored=Read-QuickRunPlan $temp
    Assert ($restored.IncludeOptionalDrivers -and (Get-QuickRunTask $restored) -eq 'Install') 'Checkpoint must preserve options and next task.'
    $plan.LastBootId=(Get-Date).ToUniversalTime().ToString('o')
    Write-QuickRunPlan $plan $temp
    $restored=Read-QuickRunPlan $temp
    Assert ($restored.LastBootId -eq $plan.LastBootId) 'JSON date conversion must preserve the boot identity.'
    $restored.Stage=99
    Write-QuickRunPlan $restored $temp
    $rejected=$false
    try { Read-QuickRunPlan $temp | Out-Null } catch {$rejected=$true}
    Assert $rejected 'Invalid checkpoints must fail closed.'
    $plan=New-QuickRunPlan -BootId 'boot-1'
    $plan.Stage=4; $plan.Status='Complete'
    Write-QuickRunPlan $plan $temp
    $rejected=$false
    try { Read-QuickRunPlan $temp | Out-Null } catch {$rejected=$true}
    Assert $rejected 'An incomplete result list must never be accepted as completed.'
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
function Driver([string]$Id,[bool]$Assigned=$true,[bool]$Optional=$false,[string]$Class='Display',[bool]$Interactive=$false,[string]$Title='Device driver') {
    [pscustomobject]@{Title=$Title;DriverHardwareID=$Id;IsAssigned=$Assigned;BrowseOnly=$Optional;DriverClass=$Class;InstallationBehavior=[pscustomobject]@{CanRequestUserInput=$Interactive}}
}
$drivers=@((Driver 'a'),(Driver 'b' $false $true),(Driver 'c' $true $false 'Firmware'),(Driver 'd' $true $false 'System' $false 'BIOS update'),(Driver 'e' $true $false 'Display' $true))
$selected=@(Select-DriverUpdates $drivers)
Assert ($selected.Count -eq 1 -and $selected[0].DriverHardwareID -eq 'a') 'Default driver mode must exclude optional, firmware and interactive updates.'
$selected=@(Select-DriverUpdates $drivers $true)
Assert ($selected.Count -eq 2) 'Optional drivers require an explicit opt-in.'
$selected=@(Select-DriverUpdates @((Driver 'a'),(Driver 'a' $false $true)) $true)
Assert ($selected.Count -eq 1 -and $selected[0].IsAssigned) 'Recommended driver wins over an alternative for the same hardware ID.'
$selected=@(Select-DriverUpdates @((Driver 'a' $false $true),(Driver 'a' $false $true)) $true)
Assert ($selected.Count -eq 0) 'Ambiguous optional alternatives require manual selection.'
$selected=@(Select-DriverUpdates @((Driver '')) $true)
Assert ($selected.Count -eq 0) 'Missing hardware metadata must require manual review.'
Write-Output 'PASS: order, independent failures, restart resume, restart cap, checkpoint validation and driver selection.'

# Mock Defender and management cmdlets inside the worker module: no OS APIs are invoked.
Import-Module (Join-Path $root 'Programm/Module/Updates.psm1') -Force
& (Get-Module Updates) {
    function script:Import-Module { param($Name,$ErrorAction) }
    function script:Update-MpSignature { param($ErrorAction) $script:SignatureCalls++ }
    function script:Get-MpComputerStatus { param($ErrorAction) $script:FakeStatus }
    function script:Get-MpPreference { param($ErrorAction) $script:FakePreferences }
    function script:Test-Path { param($Path) $script:HasPolicy }
    function script:Assert-UnmanagedDevice { if ($script:Managed) {throw 'Managed device'} }
    function script:Set-MpPreference {
        param($DisableRealtimeMonitoring,$DisableBehaviorMonitoring,$DisableIOAVProtection,$DisableOnAccessProtection,$ErrorAction)
        $script:SetCalls++
        $script:FakeStatus.RealTimeProtectionEnabled=$true
        $script:FakeStatus.BehaviorMonitorEnabled=$true
        $script:FakeStatus.IoavProtectionEnabled=$true
        $script:FakeStatus.OnAccessProtectionEnabled=$true
    }
    function Reset-Fake {
        $script:Managed=$false; $script:HasPolicy=$false; $script:SetCalls=0; $script:SignatureCalls=0
        $script:FakePreferences=[pscustomobject]@{DisableRealtimeMonitoring=$true;DisableBehaviorMonitoring=$true;DisableIOAVProtection=$true;DisableOnAccessProtection=$true}
        $script:FakeStatus=[pscustomobject]@{AMServiceEnabled=$true;AntivirusEnabled=$true;AMRunningMode='Normal';IsTamperProtected=$false;RealTimeProtectionEnabled=$false;BehaviorMonitorEnabled=$false;IoavProtectionEnabled=$false;OnAccessProtectionEnabled=$false;AntivirusSignatureAge=0;AntivirusSignatureLastUpdated=(Get-Date)}
    }
    $folder=Join-Path ([IO.Path]::GetTempPath()) ('wfw-defender-test-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $folder | Out-Null
    try {
        $log=Join-Path $folder 'details.txt'
        Reset-Fake
        $r=Invoke-DefenderProtection $log
        if ($r.Outcome -ne 'Done' -or $script:SetCalls -ne 1) {throw 'Supported protections must be enabled and verified.'}
        Reset-Fake; $script:FakeStatus.IsTamperProtected=$true
        $r=Invoke-DefenderProtection $log
        if ($r.Outcome -ne 'Attention' -or $script:SetCalls -ne 0) {throw 'Tamper protection must never be bypassed.'}
        Reset-Fake; $script:Managed=$true
        $r=Invoke-DefenderProtection $log
        if ($r.Outcome -ne 'Attention' -or $script:SetCalls -ne 0) {throw 'Managed settings must not be changed.'}
        Reset-Fake; $script:HasPolicy=$true
        $r=Invoke-DefenderProtection $log
        if ($script:SetCalls -ne 0) {throw 'Defender policy must be respected.'}
        Reset-Fake; $script:FakeStatus.AMRunningMode='Passive'
        $r=Invoke-DefenderProtection $log
        if ($r.Outcome -ne 'Attention' -or $script:SetCalls -ne 0 -or $script:SignatureCalls -ne 0) {throw 'Another antivirus must not be replaced.'}
        Write-Output 'PASS: Defender enabling, verified status, tamper protection, managed policies and alternate antivirus.'
    } finally { Remove-Item -LiteralPath $folder -Recurse -Force }
}

# Exercise GUI result handling without WPF, using its real function and fake controls.
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Programm/QuickRun.Gui.ps1'),[ref]$tokens,[ref]$parseErrors)
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Complete-QuickWorker'},$true)
. ([scriptblock]::Create($function.Extent.Text))
function Get-QuickText([string]$Key) {$Key}
function Get-UiText([string]$Key) {$Key}
function Add-Event($Message) {}
function Save-QuickState {}
function Save-Report {}
function Set-Busy([bool]$Value) {$script:Busy=$Value}
function Update-QuickView {}
function Start-QuickNext {$script:NextCalls++}
function Begin-RestartCountdown {$script:CountdownCalls++}
$script:Timer=[pscustomobject]@{}
$script:Timer | Add-Member ScriptMethod Stop {}
$script:Ui=@{NextHint=[pscustomobject]@{Text=''}}
$script:States=@('Offen')*8
$script:Messages=@('')*8
$script:DetailLogs=@('')*8
$script:NextCalls=0; $script:CountdownCalls=0; $script:ActiveProcess=$null
$script:QuickPlan=New-QuickRunPlan -BootId 'boot-1'
Complete-QuickWorker (Result 'DefenderSecure')
Assert ($script:States[5] -eq 'Automatisch bearbeitet' -and $script:NextCalls -eq 1) 'Defender result must update its screen and launch exactly one next stage.'
Complete-QuickWorker (Result 'Install' 'Attention')
Complete-QuickWorker (Result 'Windows')
Complete-QuickWorker (Result 'Drivers')
Assert ($script:QuickPlan.Status -eq 'Complete' -and $script:States[0] -eq 'Bitte prüfen' -and $script:States[3] -eq 'Bitte prüfen') 'Aggregate success must never hide an application failure.'
Assert ($script:States[1] -eq 'Automatisch bearbeitet' -and $script:NextCalls -eq 3) 'Drivers must be recorded without launching an extra stage.'
$script:QuickPlan=New-QuickRunPlan -BootId 'boot-1'
$script:ActiveTask='DefenderSecure'
Complete-QuickWorker $null
Assert ($script:QuickPlan.Results[0].Outcome -eq 'Attention') 'Missing result must be reported as attention.'
Set-QuickRunResult $script:QuickPlan (Result 'Install')
Complete-QuickWorker (Result 'Windows' 'RestartNeeded' $true)
Assert ($script:CountdownCalls -eq 1 -and $script:States[0] -eq 'Neustart nötig') 'Successful reboot-required result starts one countdown.'
Resume-QuickRunPlan $script:QuickPlan 'boot-2'
Complete-QuickWorker (Result 'Windows' 'Attention' $true)
Assert ($script:CountdownCalls -eq 1) 'A partial failure must not start another automatic countdown.'
Write-Output 'PASS: GUI chaining, component results, aggregate failure, missing result and restart behavior.'

# Simulate reopening after a reboot: recent consent plus changed boot is mandatory.
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Initialize-QuickSession'},$true)
. ([scriptblock]::Create($function.Extent.Text))
function Read-QuickRunPlan {param($Path) $script:SavedPlan}
function Get-QuickBootId {'boot-2'}
$script:Window=[pscustomobject]@{AutoResumeScheduled=$false}
$script:Window | Add-Member ScriptMethod Add_ContentRendered {param($Handler) $this.AutoResumeScheduled=$true}
$script:Ui.LanguageSwitch=[pscustomobject]@{SelectedIndex=0}
$script:StepsByLanguage=@{de=@();en=@()}
$script:Resume=$true; $script:ResumeQuickRun=$true
$script:SavedPlan=New-QuickRunPlan -BootId 'boot-1'
Set-QuickRunResult $script:SavedPlan (Result 'DefenderSecure')
Set-QuickRunResult $script:SavedPlan (Result 'Install')
Set-QuickRunResult $script:SavedPlan (Result 'Windows' 'RestartNeeded' $true)
$script:SavedPlan.RegisteredResume=$true
Initialize-QuickSession
Assert ($script:Window.AutoResumeScheduled -and (Get-QuickRunTask $script:QuickPlan) -eq 'Windows') 'Recent registered restart on a new boot must schedule continuation.'
$script:Window.AutoResumeScheduled=$false
$script:SavedPlan=New-QuickRunPlan -BootId 'boot-1'
Set-QuickRunResult $script:SavedPlan (Result 'DefenderSecure' 'RestartNeeded' $true)
$script:SavedPlan.RegisteredResume=$false
Initialize-QuickSession
Assert (-not $script:Window.AutoResumeScheduled) 'Postponement must revoke automatic continuation.'
$script:SavedPlan.RegisteredResume=$true
$script:SavedPlan.ResumeConsentAt=(Get-Date).AddDays(-8).ToString('o')
Initialize-QuickSession
Assert (-not $script:Window.AutoResumeScheduled) 'Stale restart consent must not trigger automatic updates.'
$script:SavedPlan.ResumeConsentAt=(Get-Date).ToString('o')
$script:SavedPlan.LastBootId='boot-2'
Initialize-QuickSession
Assert (-not $script:Window.AutoResumeScheduled) 'Relaunching on the same boot must not act as a reboot.'
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-QuickNext'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$script:QuickActive=$true
function Start-Task {throw 'A duplicate worker was launched.'}
Start-QuickNext
Write-Output 'PASS: reboot consent, stale checkpoints, postponement, same-boot guard and duplicate-worker guard.'
