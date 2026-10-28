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
$personalData = Join-Path $taskRoot 'personal-data'
$baselineInstaller = Join-Path $taskRoot 'upstream-setup.exe'
$sentinel = Join-Path $originalData 'personal-isolation-sentinel.txt'
$originalKey = 'HKLM:\Software\Metasequoia\MetasequoiaIME'
$personalKey = 'HKLM:\Software\Chengjiang\PersonalIME'
$originalClsid = '{E3062E9A-D834-4637-8958-ED8CFA427D01}'
$personalClsid = '{56A47253-A7C1-53AC-9028-7297207BD972}'
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

function Assert-OriginalIntact([string]$ServerPath, [int]$ProcessId) {
    if ([IO.File]::ReadAllText($sentinel) -ne $sentinelValue) { throw 'Upstream data changed.' }
    $state = Get-ItemProperty -LiteralPath $originalKey
    if ($state.DataDir -ne $originalData -or $state.ServerPath -ne $ServerPath) {
        throw 'Upstream registry paths changed.'
    }
    if (-not (Test-Path -LiteralPath $ServerPath -PathType Leaf)) { throw 'Upstream Server disappeared.' }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'Upstream Server was stopped.' }
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
$blocked = Run-Installer $PersonalInstaller $originalData (Join-Path $taskRoot 'blocked.log')
if ($blocked -eq 0) { throw 'Personal installer accepted the upstream data directory.' }
Assert-OriginalIntact $originalServer $originalProcess.Id

$code = Run-Installer $PersonalInstaller $personalData (Join-Path $taskRoot 'personal.log')
if ($code -ne 0) { throw "Personal installation failed: $code" }
$personalState = Get-ItemProperty -LiteralPath $personalKey
if ($personalState.DataDir -ne $personalData -or $personalState.ServerPath -notmatch 'ChengjiangImeServer\.exe$') {
    throw 'Personal installation did not write isolated paths.'
}
if (-not (Test-Path -LiteralPath (Join-Path $personalData 'msime.db') -PathType Leaf)) {
    throw 'Personal dictionary was not generated.'
}
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
    if ((Get-RegisteredDll $personalClsid $view) -notmatch '(?i)\\IME\\ChengjiangIME\\') {
        throw "Personal TSF registration did not use the isolated directory in $view."
    }
}
Assert-OriginalIntact $originalServer $originalProcess.Id

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
if (Test-Path -LiteralPath $personalKey) { throw 'Personal registry entry remained after uninstall.' }
Write-Host 'Side-by-side install, overlap rejection and personal uninstall preserved the upstream IME.'
