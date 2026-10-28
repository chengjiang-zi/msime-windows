param(
    [Parameter(Mandatory)][string]$PersonalInstaller,
    [Parameter(Mandatory)][string]$DevCertificate
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# This script installs and uninstalls input methods. Never run it on a user's PC
# or a persistent/self-hosted runner: GitHub discards this VM after the job.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Side-by-side installation tests require a disposable GitHub-hosted Windows runner.'
}

$taskRoot = [IO.Path]::GetFullPath((Join-Path $env:RUNNER_TEMP 'chengjiang-side-by-side'))
$runnerRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
if (-not $taskRoot.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $taskRoot)) {
    throw 'Refusing to use an existing or non-runner test directory.'
}
New-Item -ItemType Directory -Path $taskRoot | Out-Null
$originalData = Join-Path $taskRoot 'upstream-data'
$personalRoot = Join-Path $taskRoot 'personal-data'
$personalData = Join-Path $personalRoot 'chengjiangime'
$personalSentinel = Join-Path $personalRoot 'unrelated-user-file.txt'
$programSentinel = Join-Path $env:ProgramFiles 'chengjiangime\server\unrelated-user-file.txt'
$baselineInstaller = Join-Path $taskRoot 'upstream-setup.exe'
$sentinel = Join-Path $originalData 'personal-isolation-sentinel.txt'
$originalKey = 'HKLM:\Software\Metasequoia\MetasequoiaIME'
$personalKey = 'HKLM:\Software\Chengjiang\PersonalIME'
$originalClsid = '{E3062E9A-D834-4637-8958-ED8CFA427D01}'
$personalClsid = '{56A47253-A7C1-53AC-9028-7297207BD972}'
$originalProfile = '0804:{E3062E9A-D834-4637-8958-ED8CFA427D01}{4D59B1B4-D503-44AE-9259-BAD9BB2778AB}'
$personalProfile = '0804:{56A47253-A7C1-53AC-9028-7297207BD972}{1CAC6601-4479-55C1-BCA3-2B46B9AFD375}'
$sentinelValue = 'upstream data must remain untouched'

function Run-Installer([string]$File, [string]$DataDir, [string]$Log) {
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
        "/DATADIR=`"$DataDir`"", "/LOG=`"$Log`"")
    $process = Start-Process -FilePath $File -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}

function Get-RegisteredDll([string]$Clsid, [Microsoft.Win32.RegistryView]$View) {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
    try {
        $key = $base.OpenSubKey("Software\Classes\CLSID\$Clsid\InprocServer32")
        if (-not $key) { throw "Missing COM registration for $Clsid in $View" }
        try { return [string]$key.GetValue('') } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Is-KeyboardListed([string]$Profile) {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $base.OpenSubKey('Control Panel\International\User Profile\zh-Hans-CN')
        if (-not $key) { return $false }
        try { return $null -ne $key.GetValue($Profile) } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Assert-OriginalIntact([string]$ServerPath, [int]$ProcessId) {
    if ([IO.File]::ReadAllText($sentinel) -ne $sentinelValue) { throw 'Upstream data changed.' }
    $state = Get-ItemProperty -LiteralPath $originalKey
    if ($state.DataDir -ne $originalData -or $state.ServerPath -ne $ServerPath) {
        throw 'Upstream registry paths changed.'
    }
    if (-not (Test-Path -LiteralPath $ServerPath -PathType Leaf)) { throw 'Upstream Server disappeared.' }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'Upstream Server was stopped.' }
    if (-not (Is-KeyboardListed $originalProfile)) { throw 'Upstream keyboard profile disappeared.' }
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        if ((Get-RegisteredDll $originalClsid $view) -notmatch '(?i)\\IME\\MetasequoiaIME\\') {
            throw "Upstream TSF registration changed in $view."
        }
    }
}

$upstreamUrl = 'https://github.com/metasequoiaime/msime-windows/releases/download/v0.12.0/MetasequoiaIME_Setup_v0.12.0.exe'
Invoke-WebRequest -Uri $upstreamUrl -OutFile $baselineInstaller
if ((Get-FileHash -LiteralPath $baselineInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    '2baf40185ab95b109f2fd42087a1bf90ae1bb0e8298311d17031c4fccc2bb933') {
    throw 'Upstream installer hash mismatch.'
}
if ((Get-AuthenticodeSignature -LiteralPath $baselineInstaller).Status -ne 'Valid') {
    throw 'Upstream installer signature is invalid.'
}

# Only this disposable VM trusts the per-run test certificate.
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($DevCertificate)
if ($certificate.Subject -ne 'CN=Chengjiang IME Personal Dev Build Code Signing') {
    throw 'Unexpected personal development certificate.'
}
Import-Certificate -FilePath $DevCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $DevCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

# The hosted image may start with only English in its user language list.
# Add Simplified Chinese in this disposable VM so keyboard registration is real.
$languages = Get-WinUserLanguageList
if (-not ($languages | Where-Object { $_.LanguageTag -like 'zh-*' })) {
    $languages.Add('zh-Hans-CN')
    Set-WinUserLanguageList -LanguageList $languages -Force
}

$code = Run-Installer $baselineInstaller $originalData (Join-Path $taskRoot 'upstream.log')
if ($code -ne 0) { throw "Upstream installation failed: $code" }
$originalState = Get-ItemProperty -LiteralPath $originalKey
if ($originalState.DataDir -ne $originalData) { throw 'Unexpected upstream data path.' }
$originalServer = $originalState.ServerPath
if (-not (Test-Path -LiteralPath (Join-Path $originalData 'msime.db') -PathType Leaf)) {
    throw 'Upstream dictionary was not generated.'
}
[IO.File]::WriteAllText($sentinel, $sentinelValue)

$originalProcess = Get-Process -Name 'MetasequoiaImeServer' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $originalProcess) {
    $originalProcess = Start-Process -FilePath $originalServer -ArgumentList '--watchdog-managed', '--pipe-probe' `
        -WorkingDirectory (Split-Path -Parent $originalServer) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    $originalProcess.Refresh()
    if ($originalProcess.HasExited) { throw "Upstream Server did not stay running: $($originalProcess.ExitCode)" }
}
Assert-OriginalIntact $originalServer $originalProcess.Id

# The personal installer must reject the upstream data path before it can stop
# any process, migrate data or delete files.
$blockedLog = Join-Path $taskRoot 'blocked.log'
$blocked = Run-Installer $PersonalInstaller $originalData $blockedLog
if ($blocked -eq 0) { throw 'Personal installer accepted the upstream data directory.' }
if (-not (Test-Path -LiteralPath $blockedLog -PathType Leaf) -or
    (Get-Content -LiteralPath $blockedLog -Raw) -notmatch '个人版数据目录不能与原版') {
    throw 'The overlapping path did not fail for the expected isolation reason.'
}
Assert-OriginalIntact $originalServer $originalProcess.Id

# A nonempty selected directory belongs to the user, so installation must use
# a child directory and leave its existing content intact after uninstall.
New-Item -ItemType Directory -Path $personalRoot | Out-Null
[IO.File]::WriteAllText($personalSentinel, 'unrelated user file')
New-Item -ItemType Directory -Path (Split-Path -Parent $programSentinel) -Force | Out-Null
[IO.File]::WriteAllText($programSentinel, 'unrelated program file')
$code = Run-Installer $PersonalInstaller $personalRoot (Join-Path $taskRoot 'personal.log')
if ($code -ne 0) { throw "Personal installation failed: $code" }
$personalState = Get-ItemProperty -LiteralPath $personalKey
if ($personalState.DataDir -ne $personalData -or $personalState.ServerPath -notmatch 'ChengjiangImeServer\.exe$') {
    throw 'Personal installation did not write isolated paths.'
}
if (-not (Test-Path -LiteralPath (Join-Path $personalData 'msime.db') -PathType Leaf)) {
    throw 'Personal dictionary was not generated.'
}
if (-not (Is-KeyboardListed $personalProfile)) { throw 'Personal keyboard profile was not added.' }
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
    if ((Get-RegisteredDll $personalClsid $view) -notmatch '(?i)\\IME\\ChengjiangIME\\') {
        throw "Personal TSF registration did not use the isolated directory in $view."
    }
}
Assert-OriginalIntact $originalServer $originalProcess.Id

# A damaged personal registry entry must not turn the next upgrade into a
# migration from the upstream data directory.
$tamperedLog = Join-Path $taskRoot 'tampered-previous-data.log'
try {
    Set-ItemProperty -LiteralPath $personalKey -Name DataDir -Value $originalData
    $code = Run-Installer $PersonalInstaller $personalRoot $tamperedLog
    if ($code -eq 0 -or -not (Test-Path -LiteralPath $tamperedLog -PathType Leaf) -or
        (Get-Content -LiteralPath $tamperedLog -Raw) -notmatch '个人版原数据目录与原版') {
        throw 'The installer did not reject the unsafe previous data path.'
    }
    Assert-OriginalIntact $originalServer $originalProcess.Id
} finally {
    Set-ItemProperty -LiteralPath $personalKey -Name DataDir -Value $personalData
}

# Both servers must be able to coexist. Probe the personal edition over its
# actual named pipes while the upstream server remains alive.
$personalProcess = Get-Process -Name 'ChengjiangImeServer' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $personalProcess) {
    $personalProcess = Start-Process -FilePath $personalState.ServerPath `
        -ArgumentList '--watchdog-managed', '--pipe-probe' `
        -WorkingDirectory (Split-Path -Parent $personalState.ServerPath) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    $personalProcess.Refresh()
    if ($personalProcess.HasExited) { throw "Personal Server did not stay running: $($personalProcess.ExitCode)" }
}
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$probeBuild = Join-Path $taskRoot 'pipe-probe'
cmake -S (Join-Path $repoRoot 'tests/pipe-probe') -B $probeBuild -A x64 `
    "-DMSIME_CONTRACTS_DIR=$(Join-Path $repoRoot 'engine/contracts')"
if ($LASTEXITCODE -ne 0) { throw 'Personal IPC probe configuration failed.' }
cmake --build $probeBuild --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw 'Personal IPC probe build failed.' }
& (Join-Path $probeBuild 'Release/msime-ipc-probe.exe')
if ($LASTEXITCODE -ne 0) { throw 'Personal Server did not accept the isolated IPC probe.' }
Assert-OriginalIntact $originalServer $originalProcess.Id

$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{C4548683-2C88-54A9-A7AE-CD6008F8154C}_is1'
$uninstallState = Get-ItemProperty -LiteralPath $uninstallKey
$expectedInstall = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'chengjiangime')).TrimEnd('\')
$actualInstall = [IO.Path]::GetFullPath($uninstallState.InstallLocation).TrimEnd('\')
if (-not [string]::Equals($expectedInstall, $actualInstall, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unexpected personal uninstall location.'
}
$uninstaller = Join-Path $actualInstall 'unins000.exe'
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { throw 'Personal uninstaller is missing.' }
$uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' `
    -WindowStyle Hidden -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw "Personal uninstall failed: $($uninstall.ExitCode)" }
Assert-OriginalIntact $originalServer $originalProcess.Id
if ([IO.File]::ReadAllText($personalSentinel) -ne 'unrelated user file') {
    throw 'Personal uninstall changed an unrelated file in the selected parent directory.'
}
if ([IO.File]::ReadAllText($programSentinel) -ne 'unrelated program file') {
    throw 'Personal installation or uninstall changed an unrelated file in the program directory.'
}
if (Is-KeyboardListed $personalProfile) { throw 'Personal keyboard profile remained after uninstall.' }
$remaining = Get-ItemProperty -LiteralPath $personalKey -ErrorAction SilentlyContinue
if ($remaining) {
    foreach ($name in @('DataDir', 'ServerPath', 'VersionDir', 'GameCompatProfileName')) {
        if ($remaining.PSObject.Properties[$name]) { throw "Personal registry value remained after uninstall: $name" }
    }
}
Write-Host 'Side-by-side install, overlap rejection and personal uninstall preserved the upstream IME.'
