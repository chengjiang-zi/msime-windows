$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
    throw 'Standard-user task testing requires a disposable GitHub-hosted Windows runner.'
}

$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$userName = 'cjtest' + $suffix
$taskName = 'ChengjiangImeTest-' + $suffix
$createdUser = $false
try {
    $password = ConvertTo-SecureString ([Guid]::NewGuid().ToString('N') + 'aA9!') -AsPlainText -Force
    $user = New-LocalUser -Name $userName -Password $password -PasswordNeverExpires
    $createdUser = $true
    $account = "$env:COMPUTERNAME\$userName"
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\notepad.exe')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
    $principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    try {
        $taskSid = ([Security.Principal.NTAccount]::new($task.Principal.UserId)).Translate(
            [Security.Principal.SecurityIdentifier])
    } catch {
        $taskSid = [Security.Principal.SecurityIdentifier]::new($task.Principal.UserId)
    }
    if ($taskSid.Value -ne $user.SID.Value) { throw 'Task was not registered for the standard user.' }
    Write-Host 'PASS: administrator can register an interactive logon task for the standard user without a password.'
} finally {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    if ($createdUser) { Remove-LocalUser -Name $userName }
}
