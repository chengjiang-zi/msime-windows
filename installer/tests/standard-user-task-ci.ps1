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
    $credential = [Management.Automation.PSCredential]::new($account, $password)
    $exe = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $arguments = @('/Create', '/F', '/TN', "`"$taskName`"", '/SC', 'ONLOGON', '/RL', 'LIMITED', '/IT',
        '/TR', "`"$env:SystemRoot\System32\notepad.exe`"")
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -Credential $credential `
        -LoadUserProfile -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Standard-user scheduled task creation timed out.'
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) { throw "Standard-user scheduled task creation failed: $($process.ExitCode)" }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    try {
        $taskSid = ([Security.Principal.NTAccount]::new($task.Principal.UserId)).Translate(
            [Security.Principal.SecurityIdentifier])
    } catch {
        $taskSid = [Security.Principal.SecurityIdentifier]::new($task.Principal.UserId)
    }
    if ($taskSid.Value -ne $user.SID.Value) { throw 'Task was not registered for the standard user.' }
    Write-Host 'PASS: standard user can create an interactive logon task for their own account.'
} finally {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    if ($createdUser) { Remove-LocalUser -Name $userName }
}
