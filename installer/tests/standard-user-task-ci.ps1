$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
    throw 'Standard-user task testing requires a disposable GitHub-hosted Windows runner.'
}

$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$userName = 'cjtest' + $suffix
$taskName = 'ChengjiangImeTest-' + $suffix
$probeRoot = Join-Path $env:PUBLIC $taskName
$probeExe = Join-Path $probeRoot 'probe.exe'
$probeResult = Join-Path $probeRoot 'result.txt'
$probeLog = Join-Path $probeRoot 'probe.log'
$createdUser = $false
try {
    $password = ConvertTo-SecureString ([Guid]::NewGuid().ToString('N') + 'aA9!') -AsPlainText -Force
    $user = New-LocalUser -Name $userName -Password $password -PasswordNeverExpires
    $createdUser = $true
    New-Item -ItemType Directory -Path $probeRoot | Out-Null
    & "$env:SystemRoot\System32\icacls.exe" $probeRoot /grant "*$($user.SID.Value):(OI)(CI)M" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not grant the test user access to the probe directory.' }
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
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    $definition = $service.NewTask(0)
    $definition.Principal.UserId = $user.SID.Value
    $definition.Principal.LogonType = 3
    $definition.Principal.RunLevel = 0
    $trigger = $definition.Triggers.Create(9)
    $trigger.UserId = $user.SID.Value
    $taskAction = $definition.Actions.Create(0)
    $taskAction.Path = Join-Path $env:SystemRoot 'System32\notepad.exe'
    $registered = $folder.RegisterTaskDefinition($taskName, $definition, 6, $user.SID.Value, $null, 3, $null)
    if (-not $registered) { throw 'Direct scheduler COM registration returned no task.' }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host 'PASS: scheduler COM accepts the standard user SID.'
    $registered = $folder.RegisterTask($taskName, $definition.XmlText, 6, $user.SID.Value, '', 3)
    if (-not $registered) { throw 'Scheduler XML registration returned no task.' }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host 'PASS: scheduler accepts XML and an empty password.'

    $compiler = (Get-Command ISCC.exe -CommandType Application -ErrorAction Stop).Source
    $build = Join-Path $env:RUNNER_TEMP $taskName
    New-Item -ItemType Directory -Path $build | Out-Null
    & $compiler '/Qp' "/O$build" (Join-Path $PSScriptRoot 'watchdog-task-probe.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile watchdog task probe.' }
    $taskResult = Join-Path $build 'task-result.txt'
    $taskLog = Join-Path $build 'task-probe.log'
    $taskProbe = Join-Path $build 'watchdog-task-probe.exe'
    $process = Start-Process -FilePath $taskProbe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES',
        "/SID=$($user.SID.Value)", "/TASK=$taskName", "/RESULT=`"$taskResult`"", "/LOG=`"$taskLog`"") `
        -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Inno task probe timed out.'
    }
    if (-not (Test-Path -LiteralPath $taskResult) -or [IO.File]::ReadAllText($taskResult).Trim() -ne 'registered') {
        if (Test-Path -LiteralPath $taskLog) { Get-Content -LiteralPath $taskLog | Select-Object -Last 30 | Write-Host }
        throw 'Inno task probe did not register the standard user task.'
    }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    try {
        $taskSid = ([Security.Principal.NTAccount]::new($task.Principal.UserId)).Translate(
            [Security.Principal.SecurityIdentifier])
    } catch {
        $taskSid = [Security.Principal.SecurityIdentifier]::new($task.Principal.UserId)
    }
    if ($taskSid.Value -ne $user.SID.Value) { throw 'Inno task probe registered the wrong user.' }
    Write-Host 'PASS: Inno registered an interactive task for the standard user.'
    & $compiler '/Qp' "/O$build" (Join-Path $PSScriptRoot 'interactive-user-probe.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile interactive user probe.' }
    Copy-Item -LiteralPath (Join-Path $build 'interactive-user-probe.exe') -Destination $probeExe
    $process = Start-Process -FilePath $probeExe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES',
        "/RESULT=`"$probeResult`"") -WindowStyle Hidden -Wait -PassThru
    if (-not (Test-Path -LiteralPath $probeResult -PathType Leaf)) { throw 'Same-account probe produced no result.' }
    $lines = [IO.File]::ReadAllLines($probeResult)
    if ($lines[0] -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
        $lines[1] -ne $env:LOCALAPPDATA) {
        throw 'Same-account shell-user lookup returned an unexpected result.'
    }
    Remove-Item -LiteralPath $probeResult -Force
    $credential = [Management.Automation.PSCredential]::new($account, $password)
    # Start-Process -Credential inherits the runner's environment, including
    # its private TEMP directory. Give the child a writable temporary directory.
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    try {
        $env:TEMP = $probeRoot
        $env:TMP = $probeRoot
        $process = Start-Process -FilePath $probeExe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES',
            "/RESULT=`"$probeResult`"", "/LOG=`"$probeLog`"") -Credential $credential -LoadUserProfile `
            -WorkingDirectory $probeRoot -WindowStyle Hidden -PassThru
    } finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
    }
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Different-account shell-user probe timed out.'
    }
    if (-not (Test-Path -LiteralPath $probeResult -PathType Leaf)) {
        $process.Refresh()
        if (Test-Path -LiteralPath $probeLog) { Get-Content -LiteralPath $probeLog | Write-Host }
        throw "Shell-user probe produced no result (exit $($process.ExitCode))."
    }
    $lines = [IO.File]::ReadAllLines($probeResult)
    $shellOwner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($lines[0] -ne 'unavailable' -and $lines[0] -ne $shellOwner) {
        throw 'Shell-user probe returned the wrong account.'
    }
    if ($lines[0] -eq 'unavailable') {
        Write-Host 'PASS: different-account shell lookup failed closed.'
    } else {
        Write-Host 'PASS: different-account probe identified the desktop owner.'
    }
} finally {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    if ($createdUser) { Remove-LocalUser -Name $userName }
    if (Test-Path -LiteralPath $probeExe) { Remove-Item -LiteralPath $probeExe -Force }
    if (Test-Path -LiteralPath $probeResult) { Remove-Item -LiteralPath $probeResult -Force }
    if (Test-Path -LiteralPath $probeLog) { Remove-Item -LiteralPath $probeLog -Force }
    if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Force -ErrorAction SilentlyContinue }
}
