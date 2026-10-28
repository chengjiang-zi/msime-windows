$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Alternate-admin testing requires a disposable GitHub-hosted Windows runner.'
}

$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$userName = 'cjadmin' + $suffix
$createdUser = $false
try {
    $plainPassword = [Guid]::NewGuid().ToString('N') + 'aA9!'
    $password = ConvertTo-SecureString $plainPassword -AsPlainText -Force
    $user = New-LocalUser -Name $userName -Password $password -PasswordNeverExpires
    $createdUser = $true
    $administrators = Get-LocalGroup -SID 'S-1-5-32-544'
    Add-LocalGroupMember -Group $administrators -Member $user

    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
    $root = Join-Path $env:RUNNER_TEMP ('alternate-admin-' + $suffix)
    New-Item -ItemType Directory -Path $root | Out-Null
    $build = Join-Path $root 'build'
    cmake -S (Join-Path $repoRoot 'tests/alternate-admin-launch') -B $build -A x64
    if ($LASTEXITCODE -ne 0) { throw 'Alternate-admin launcher configuration failed.' }
    cmake --build $build --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Alternate-admin launcher build failed.' }
    $compiler = (Get-Command ISCC.exe -CommandType Application -ErrorAction Stop).Source
    & $compiler '/Qp' "/O$root" (Join-Path $PSScriptRoot 'interactive-user-probe.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile interactive-user probe.' }

    $probe = Join-Path $root 'interactive-user-probe.exe'
    $output = Join-Path $root 'result.txt'
    $log = Join-Path $root 'probe.log'
    $launcher = Join-Path $build 'Release/personal-alternate-admin-launch.exe'
    $env:CHENGJIANG_TEST_USERNAME = $userName
    $env:CHENGJIANG_TEST_PASSWORD = $plainPassword
    try {
        & $launcher $probe '/VERYSILENT' '/SUPPRESSMSGBOXES' "/RESULT=$output" "/LOG=$log"
    } finally {
        Remove-Item Env:CHENGJIANG_TEST_USERNAME -ErrorAction SilentlyContinue
        Remove-Item Env:CHENGJIANG_TEST_PASSWORD -ErrorAction SilentlyContinue
        $plainPassword = $null
    }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Select-Object -Last 30 | Write-Host }
        throw 'Alternate-admin identity probe produced no result.'
    }
    $lines = [IO.File]::ReadAllLines($output)
    if ($lines.Count -lt 3 -or $lines[0] -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
        $lines[1] -ne $env:LOCALAPPDATA -or $lines[2] -ne $user.SID.Value) {
        throw 'Alternate-admin probe did not distinguish the desktop user from the elevated account.'
    }
    Write-Host 'PASS: elevated alternate account identified the original desktop user and data directory.'
} finally {
    Remove-Item Env:CHENGJIANG_TEST_USERNAME -ErrorAction SilentlyContinue
    Remove-Item Env:CHENGJIANG_TEST_PASSWORD -ErrorAction SilentlyContinue
    if ($createdUser) { Remove-LocalUser -Name $userName }
}
