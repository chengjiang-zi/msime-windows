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
    $exe = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $arguments = @('/Create', '/F', '/TN', "`"$taskName`"", '/SC', 'ONLOGON', '/RL', 'LIMITED', '/IT',
        '/RU', "`"$account`"", '/RP', '""',
        '/TR', "`"$env:SystemRoot\System32\notepad.exe`"")
    $stdout = Join-Path $env:RUNNER_TEMP ($taskName + '-stdout.txt')
    $stderr = Join-Path $env:RUNNER_TEMP ($taskName + '-stderr.txt')
    $process = Start-Process -FilePath $exe -ArgumentList $arguments `
        -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Standard-user scheduled task creation timed out.'
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout | Write-Host }
        if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr | Write-Host }
        throw "Standard-user scheduled task creation failed: $($process.ExitCode)"
    }
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
