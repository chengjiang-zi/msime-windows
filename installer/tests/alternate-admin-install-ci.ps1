param(
    [Parameter(Mandatory)][string]$PersonalInstaller,
    [Parameter(Mandatory)][string]$DevCertificate,
    [Parameter(Mandatory)][string]$Launcher,
    [Parameter(Mandatory)][string]$TestRoot,
    [Parameter(Mandatory)][string]$DesktopSid
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Alternate-admin installation tests require a disposable GitHub-hosted Windows runner.'
}

$originalKey = 'HKLM:\Software\Metasequoia\MetasequoiaIME'
$personalKey = 'HKLM:\Software\Chengjiang\PersonalIME'
$originalProfile = '0804:{E3062E9A-D834-4637-8958-ED8CFA427D01}{4D59B1B4-D503-44AE-9259-BAD9BB2778AB}'
$personalProfile = '0804:{56A47253-A7C1-53AC-9028-7297207BD972}{1CAC6601-4479-55C1-BCA3-2B46B9AFD375}'
$keyboardKey = 'Registry::HKEY_USERS\' + $DesktopSid + '\Control Panel\International\User Profile\zh-Hans-CN'
function Has-Profile([string]$Profile) {
    $key = Get-Item -LiteralPath $keyboardKey -ErrorAction SilentlyContinue
    return $null -ne $key -and $null -ne $key.GetValue($Profile)
}
function Run-Alternate([string]$File, [string]$Log) {
    & $Launcher $File '/VERYSILENT' '/SUPPRESSMSGBOXES' '/NORESTART' "/LOG=$Log" | ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    if ($code -ne 0 -and (Test-Path -LiteralPath $Log)) {
        Get-Content -LiteralPath $Log | Select-Object -Last 50 | Write-Host
    }
    return $code
}
function Assert-OriginalIntact([string]$DataDir, [string]$ServerPath, [int]$ProcessId, [string]$Sentinel) {
    if ([IO.File]::ReadAllText($Sentinel) -ne 'upstream data remains intact') { throw 'Upstream data changed.' }
    $state = Get-ItemProperty -LiteralPath $originalKey
    if ($state.DataDir -ne $DataDir -or $state.ServerPath -ne $ServerPath) { throw 'Upstream registry changed.' }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'Upstream Server was stopped.' }
    if (-not (Has-Profile $originalProfile)) { throw 'Upstream keyboard profile disappeared.' }
}

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($DevCertificate)
if ($certificate.Subject -ne 'CN=Chengjiang IME Personal Dev Build Code Signing') {
    throw 'Unexpected development certificate.'
}
$signature = Get-AuthenticodeSignature -LiteralPath $PersonalInstaller
if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw 'Installer signature does not match the development certificate.'
}
Import-Certificate -FilePath $DevCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $DevCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
$languages = Get-WinUserLanguageList
if (-not ($languages | Where-Object { $_.LanguageTag -like 'zh-*' })) {
    $languages.Add('zh-Hans-CN')
    Set-WinUserLanguageList -LanguageList $languages -Force
}

$baseline = Join-Path $TestRoot 'upstream-setup.exe'
Invoke-WebRequest -Uri 'https://github.com/metasequoiaime/msime-windows/releases/download/v0.12.0/MetasequoiaIME_Setup_v0.12.0.exe' -OutFile $baseline
if ((Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    '2baf40185ab95b109f2fd42087a1bf90ae1bb0e8298311d17031c4fccc2bb933' -or
    (Get-AuthenticodeSignature -LiteralPath $baseline).Status -ne 'Valid') {
    throw 'Upstream installer verification failed.'
}
$setup = Start-Process -FilePath $baseline -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' `
    -WindowStyle Hidden -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Upstream setup failed: $($setup.ExitCode)" }
$original = Get-ItemProperty -LiteralPath $originalKey
$originalData = [string]$original.DataDir
$originalServer = [string]$original.ServerPath
$sentinel = Join-Path $originalData 'alternate-admin-test-sentinel.txt'
[IO.File]::WriteAllText($sentinel, 'upstream data remains intact')
$originalProcess = Get-Process -Name 'MetasequoiaImeServer' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $originalProcess) {
    $originalProcess = Start-Process -FilePath $originalServer -ArgumentList '--watchdog-managed', '--pipe-probe' `
        -WorkingDirectory (Split-Path -Parent $originalServer) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    $originalProcess.Refresh()
    if ($originalProcess.HasExited) { throw 'Upstream Server did not stay running.' }
}
Assert-OriginalIntact $originalData $originalServer $originalProcess.Id $sentinel

$code = Run-Alternate $PersonalInstaller (Join-Path $TestRoot 'personal-alternate-install.log')
if ($code -ne 0) { throw "Alternate-admin personal installation failed: $code" }
$personal = Get-ItemProperty -LiteralPath $personalKey
$expectedData = Join-Path $env:LOCALAPPDATA 'chengjiangime'
if ($personal.DataDir -ne $expectedData) { throw "Personal data directory is not the desktop user's: $($personal.DataDir)" }
if (-not (Has-Profile $personalProfile)) { throw 'Personal profile was not registered for the desktop user.' }
$watchdog = Get-ScheduledTask -TaskName 'Chengjiang IME Watchdog' -ErrorAction Stop
try {
    $watchdogSid = ([Security.Principal.NTAccount]::new($watchdog.Principal.UserId)).Translate(
        [Security.Principal.SecurityIdentifier])
} catch {
    $watchdogSid = [Security.Principal.SecurityIdentifier]::new($watchdog.Principal.UserId)
}
if ($watchdogSid.Value -ne $DesktopSid) { throw 'Watchdog belongs to the wrong account.' }
# The finish page starts this task rather than launching into the administrator's
# session. Verify both resulting processes actually belong to the desktop user.
Start-ScheduledTask -TaskName 'Chengjiang IME Watchdog'
$deadline = (Get-Date).AddSeconds(40)
do {
    $watchdogProcess = Get-CimInstance Win32_Process -Filter "Name = 'ChengjiangImeWatchdog.exe'" |
        Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid).Sid -eq $DesktopSid } |
        Select-Object -First 1
    $serverProcess = Get-CimInstance Win32_Process -Filter "Name = 'ChengjiangImeServer.exe'" |
        Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid).Sid -eq $DesktopSid } |
        Select-Object -First 1
    if (-not $watchdogProcess -or -not $serverProcess) { Start-Sleep -Seconds 1 }
} while ((!$watchdogProcess -or !$serverProcess) -and (Get-Date) -lt $deadline)
if (-not $watchdogProcess -or -not $serverProcess) {
    throw 'The watchdog did not start both processes as the desktop user.'
}
$personalSentinel = Join-Path $personal.DataDir 'alternate-admin-test-sentinel.txt'
[IO.File]::WriteAllText($personalSentinel, 'personal data remains intact until uninstall')
Assert-OriginalIntact $originalData $originalServer $originalProcess.Id $sentinel

$uninstaller = Join-Path $env:ProgramFiles 'chengjiangime\unins000.exe'
$helper = Join-Path (Split-Path -Parent $personal.ServerPath) 'register-personal-watchdog.ps1'
$helperBackup = $helper + '.test-backup'
if (-not (Test-Path -LiteralPath $helper -PathType Leaf) -or (Test-Path -LiteralPath $helperBackup)) {
    throw 'Unexpected cleanup helper state.'
}
try {
    Move-Item -LiteralPath $helper -Destination $helperBackup
    $code = Run-Alternate $uninstaller (Join-Path $TestRoot 'personal-cleanup-failure.log')
    if ($code -eq 0 -or -not (Test-Path -LiteralPath $personalSentinel) -or -not (Has-Profile $personalProfile)) {
        throw 'Uninstall did not stop safely when interactive-user cleanup was unavailable.'
    }
    Assert-OriginalIntact $originalData $originalServer $originalProcess.Id $sentinel
} finally {
    if (Test-Path -LiteralPath $helperBackup) { Move-Item -LiteralPath $helperBackup -Destination $helper }
}

$code = Run-Alternate $uninstaller (Join-Path $TestRoot 'personal-alternate-uninstall.log')
if ($code -ne 0) { throw "Alternate-admin personal uninstall failed: $code" }
if (Has-Profile $personalProfile) { throw 'Personal profile remained in the desktop user keyboard list.' }
if (Get-ScheduledTask -TaskName 'Chengjiang IME Watchdog' -ErrorAction SilentlyContinue) {
    throw 'Personal watchdog task remained after uninstall.'
}
Assert-OriginalIntact $originalData $originalServer $originalProcess.Id $sentinel
Write-Host 'PASS: alternate administrator installed and uninstalled for the desktop user without disturbing upstream.'
