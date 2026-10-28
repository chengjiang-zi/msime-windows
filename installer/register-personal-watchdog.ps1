param(
    [Parameter(Mandatory)][string]$UserSid,
    [Parameter(Mandatory)][string]$TaskName,
    [Parameter(Mandatory)][string]$Executable,
    [string]$Arguments = '',
    [switch]$RunNow
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sid = [Security.Principal.SecurityIdentifier]::new($UserSid)
if ($Arguments) {
    $action = New-ScheduledTaskAction -Execute $Executable -Argument $Arguments
} else {
    $action = New-ScheduledTaskAction -Execute $Executable
}
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $sid.Value
$principal = New-ScheduledTaskPrincipal -UserId $sid.Value -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Force | Out-Null
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
try {
    $actualSid = ([Security.Principal.NTAccount]::new($task.Principal.UserId)).Translate(
        [Security.Principal.SecurityIdentifier])
} catch {
    $actualSid = [Security.Principal.SecurityIdentifier]::new($task.Principal.UserId)
}
if ($actualSid.Value -ne $sid.Value) { throw 'Watchdog task was registered for the wrong user.' }
if ($RunNow) { Start-ScheduledTask -TaskName $TaskName }
