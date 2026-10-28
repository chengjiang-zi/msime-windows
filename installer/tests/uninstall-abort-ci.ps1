$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Uninstall-abort testing requires a disposable GitHub-hosted Windows runner.'
}
$root = Join-Path $env:RUNNER_TEMP ('uninstall-abort-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$installDir = Join-Path $root 'installed'
$compiler = (Get-Command ISCC.exe -CommandType Application -ErrorAction Stop).Source
& $compiler '/Qp' "/O$root" (Join-Path $PSScriptRoot 'uninstall-abort-probe.iss')
if ($LASTEXITCODE -ne 0) { throw 'Could not compile uninstall-abort probe.' }
$installer = Join-Path $root 'uninstall-abort-probe.exe'
$setup = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
    "/DIR=`"$installDir`"") -WindowStyle Hidden -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Probe installation failed: $($setup.ExitCode)" }
$payload = Join-Path $installDir 'uninstall-abort-probe-payload.txt'
if (-not (Test-Path -LiteralPath $payload -PathType Leaf)) { throw 'Probe payload was not installed.' }
$uninstaller = Join-Path $installDir 'unins000.exe'
$uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' `
    -WindowStyle Hidden -PassThru
if (-not $uninstall.WaitForExit(60000)) {
    Stop-Process -Id $uninstall.Id -Force -ErrorAction SilentlyContinue
    throw 'Uninstall-abort probe timed out.'
}
$uninstall.Refresh()
if ($uninstall.ExitCode -eq 0 -or -not (Test-Path -LiteralPath $payload -PathType Leaf)) {
    throw 'An exception did not safely stop the uninstaller before deleting files.'
}
Write-Host 'PASS: uninstall exception stops before deleting the test payload.'
