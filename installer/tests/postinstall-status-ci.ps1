$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Post-install status testing requires a disposable GitHub-hosted Windows runner.'
}
$root = Join-Path $env:RUNNER_TEMP ('postinstall-status-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$compiler = (Get-Command ISCC.exe -CommandType Application -ErrorAction Stop).Source
& $compiler '/Qp' "/O$root" (Join-Path $PSScriptRoot 'postinstall-status-probe.iss')
if ($LASTEXITCODE -ne 0) { throw 'Could not compile post-install status probe.' }
$probe = Join-Path $root 'postinstall-status-probe.exe'
foreach ($case in @(@{ Arguments = @(); Expected = 0 }, @{ Arguments = @('/FAILPOSTINSTALL'); Expected = 20 })) {
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') + $case.Arguments
    $process = Start-Process -FilePath $probe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Post-install status probe timed out.'
    }
    $process.Refresh()
    if ($process.ExitCode -ne $case.Expected) {
        throw "Post-install status probe returned $($process.ExitCode); expected $($case.Expected)."
    }
}
Write-Host 'PASS: successful post-install returns zero; a post-install exception returns 20.'
