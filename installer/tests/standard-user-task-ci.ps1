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

    $compiler = (Get-Command ISCC.exe -CommandType Application -ErrorAction Stop).Source
    $build = Join-Path $env:RUNNER_TEMP $taskName
    New-Item -ItemType Directory -Path $build | Out-Null
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
    $process = Start-Process -FilePath $probeExe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES',
        "/RESULT=`"$probeResult`"", "/LOG=`"$probeLog`"") -Credential $credential -LoadUserProfile `
        -WorkingDirectory $probeRoot -WindowStyle Hidden -PassThru
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
    if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Force }
}
